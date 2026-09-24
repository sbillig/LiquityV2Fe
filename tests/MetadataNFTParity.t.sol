// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {MetadataNFT, IMetadataNFT, ITroveManager, FixedAssetReader} from "../reference/bold/contracts/src/NFTMetadata/MetadataNFT.sol";
import {TroveNFT, IAddressesRegistry, LatestTroveData} from "../reference/bold/contracts/src/TroveNFT.sol";
import {bauhaus} from "../reference/bold/contracts/src/NFTMetadata/utils/bauhaus.sol";
import {SSTORE2} from "Solady/utils/SSTORE2.sol";
import {PoolVm} from "./DefaultPoolParity.t.sol";
interface MetadataGeometryView {function image(string memory,uint256) external view returns(string memory);}
contract MetadataTokenMock {
    string private n="Wrapped Ether";string private s="WETH";uint public mode;
    function set(string memory name_,string memory symbol_) external {n=name_;s=symbol_;}
    function setMode(uint value) external {mode=value;}
    function name() external view returns(string memory){require(mode!=1&&mode!=3,"name failed");return n;}
    function symbol() external view returns(string memory){require(mode!=2&&mode!=3,"symbol failed");return s;}
}
contract MetadataCallerAssetMock {
    address public first;address public second;
    function allow(address a,address b) external {first=a;second=b;}
    function readAsset(bytes4) external view returns(string memory){require(msg.sender==first||msg.sender==second,"unexpected asset caller");return "caller-checked-asset";}
}
contract MetadataRegistryMock {
    address public immutable metadataNFT;address public immutable collToken;
    address public constant boldToken=address(0xb01d);
    address public immutable troveManager=address(this);
    constructor(address renderer,address collateral){metadataNFT=renderer;collToken=collateral;}
    function getLatestTroveData(uint256) external pure returns(LatestTroveData memory){return LatestTroveData(2000e18,5e18,0,0,0,2000e18,3e16,0,0,0);}
    function getTroveStatus(uint256) external pure returns(ITroveManager.Status){return ITroveManager.Status.active;}
}
contract MetadataNFTParityTest {
    PoolVm constant vm=PoolVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    MetadataNFT a;MetadataNFT b;FixedAssetReader readerA;FixedAssetReader readerB;MetadataTokenMock token;
    function feDeploy(string memory name,bytes memory args) internal returns(address created) {
        bytes memory code=bytes.concat(vm.parseBytes(vm.readFile(string.concat("build/",name,".bin"))),args);
        require(code.length<=49152,"EIP3860");
        assembly{created:=create(0,add(code,32),mload(code))}require(created.code.length>0,"Fe deployment");require(created.code.length<=24576,"EIP170");
    }
    function setUp() public {
        token=new MetadataTokenMock();deployRenderers(false);
    }
    function deployRenderers(bool production) internal {
        bytes4[] memory sigs=new bytes4[](5);FixedAssetReader.Asset[] memory assets=new FixedAssetReader.Asset[](5);
        string[5] memory names=["geist","BOLD","WETH","wstETH","rETH"];bytes memory payload;
        string[5] memory files=["geist","bold_logo","weth_logo","wsteth_logo","reth_logo"];
        for(uint i;i<5;i++) {
            sigs[i]=bytes4(keccak256(bytes(names[i])));uint128 start=uint128(payload.length);
            bytes memory content=production?bytes(vm.readFile(string.concat("reference/bold/contracts/utils/assets/",files[i],".txt"))):bytes(string.concat("asset-",names[i],"-data"));
            payload=bytes.concat(payload,content);
            assets[i]=FixedAssetReader.Asset(start,uint128(payload.length));
        }
        address pointer=SSTORE2.write(payload);
        readerA=FixedAssetReader(feDeploy("FixedAssetReader",abi.encode(pointer,sigs,assets)));
        readerB=new FixedAssetReader(pointer,sigs,assets);
        a=MetadataNFT(feDeploy("MetadataNFT",abi.encode(readerA)));b=new MetadataNFT(readerB);
    }
    function compare(bytes memory data) internal view returns(bool) {
        (bool x,bytes memory p)=address(a).staticcall(data);(bool y,bytes memory q)=address(b).staticcall(data);
        require(x==y,"success mismatch");require(keccak256(p)==keccak256(q),"return/revert mismatch");return x;
    }
    function sample(uint256 id) internal view returns(IMetadataNFT.TroveData memory){return IMetadataNFT.TroveData(id,address(0xabcdef),address(token),address(0xb01d),5e18,2000e18,3e16,ITroveManager.Status.active);}
    function testAssetCallsRemainInRenderer() public {
        MetadataCallerAssetMock assets=new MetadataCallerAssetMock();
        a=MetadataNFT(feDeploy("MetadataNFT",abi.encode(assets)));
        b=new MetadataNFT(FixedAssetReader(address(assets)));
        assets.allow(address(a),address(b));
        require(compare(abi.encodeCall(a.uri,(sample(7)))));
    }
    function testGeometryCompanionDeployment() public view {
        address companion=address(uint160(uint256(keccak256(abi.encodePacked(hex"d694",address(a),hex"01")))));
        require(companion.code.length>0&&companion.code.length<=24576,"geometry deployment size");
        string[4] memory symbols=["WETH","wstETH","rETH","unknown"];
        for(uint i;i<4;i++)for(uint id;id<4;id++) {
            string memory output=MetadataGeometryView(companion).image(symbols[i],id);
            require(keccak256(bytes(output))==keccak256(bytes(bauhaus._bauhaus(symbols[i],id))),"embedded geometry output");
        }
    }
    function testAllImagesAndStatuses() public {
        require(address(a.assetReader())==address(readerA)&&address(b.assetReader())==address(readerB));
        string[4] memory symbols=["WETH","wstETH","rETH","unknown"];
        for(uint s;s<4;s++) {
            token.set("Collateral token",symbols[s]);
            for(uint id;id<4;id++)for(uint status;status<5;status++) {
                IMetadataNFT.TroveData memory d=sample(id);d._status=ITroveManager.Status(status);
                require(compare(abi.encodeCall(a.attributes,(d))));require(compare(abi.encodeCall(a.dynamicTextComponents,(d))));require(compare(abi.encodeCall(a.uri,(d))));
            }
        }
    }
    function testFuzzMetadata(uint256 id,address owner,uint256 coll,uint256 debt,uint256 interest,uint8 status) public view {
        IMetadataNFT.TroveData memory d=sample(id);d._owner=owner;d._collAmount=coll;d._debtAmount=debt;d._interestRate=interest;d._status=ITroveManager.Status(status%5);
        require(compare(abi.encodeCall(a.attributes,(d))));require(compare(abi.encodeCall(a.dynamicTextComponents,(d))));require(compare(abi.encodeCall(a.uri,(d))));
    }
    function testFuzzTokenStrings(string memory name,string memory symbol) public {
        token.set(name,symbol);IMetadataNFT.TroveData memory d=sample(type(uint256).max);
        require(compare(abi.encodeCall(a.dynamicTextComponents,(d))));require(compare(abi.encodeCall(a.uri,(d))));
    }
    function testDependencyFailuresAndInvalidStatus() public {
        IMetadataNFT.TroveData memory d=sample(1);
        for(uint mode=1;mode<=3;mode++){token.setMode(mode);require(!compare(abi.encodeCall(a.uri,(d))));require(compare(abi.encodeCall(a.dynamicTextComponents,(d)))==(mode==1));require(compare(abi.encodeCall(a.attributes,(d))));}
        token.setMode(0);
        bytes memory data=abi.encodeCall(a.uri,(d));assembly{mstore(add(data,260),5)}require(!compare(data));
        data=abi.encodeCall(a.attributes,(d));assembly{mstore(add(data,260),255)}require(!compare(data));
        data=abi.encodeCall(a.dynamicTextComponents,(d));assembly{mstore(add(data,100),not(0))}require(!compare(data));
    }
    function testProductionAssets() public {
        deployRenderers(true);
        string[3] memory symbols=["WETH","wstETH","rETH"];
        for(uint i;i<3;i++) {
            token.set("Production collateral",symbols[i]);
            IMetadataNFT.TroveData memory d=sample(type(uint256).max-i);
            require(compare(abi.encodeCall(a.uri,(d))));require(compare(abi.encodeCall(a.dynamicTextComponents,(d))));
        }
    }
    function testConnectedTroveNFTMetadata() public {
        MetadataRegistryMock regA=new MetadataRegistryMock(address(a),address(token));MetadataRegistryMock regB=new MetadataRegistryMock(address(b),address(token));
        TroveNFT nftA=TroveNFT(feDeploy("TroveNFT",abi.encode(regA)));TroveNFT nftB=new TroveNFT(IAddressesRegistry(address(regB)));
        address owner=address(0xabcdef);
        vm.prank(address(regA));nftA.mint(owner,123);vm.prank(address(regB));nftB.mint(owner,123);
        require(keccak256(bytes(nftA.tokenURI(123)))==keccak256(bytes(nftB.tokenURI(123))),"connected metadata");
        vm.prank(owner);nftA.transferFrom(owner,address(0xcafe),123);vm.prank(owner);nftB.transferFrom(owner,address(0xcafe),123);
        require(keccak256(bytes(nftA.tokenURI(123)))==keccak256(bytes(nftB.tokenURI(123))),"transferred owner metadata");
    }
}
