// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {TroveNFT, LatestTroveData, ITroveManager, IMetadataNFT, IAddressesRegistry} from "../reference/bold/contracts/src/TroveNFT.sol";
import {PoolVm} from "./DefaultPoolParity.t.sol";
import {StorageVm} from "./SortedTrovesParity.t.sol";
interface NFTVm {function assume(bool) external;}
contract NFTDependencies {
    string private tokenName="Wrapped Ether";
    string private tokenSymbol="WETH";
    address public immutable troveManager=address(this);
    address public immutable collToken=address(this);
    address public immutable metadataNFT=address(this);
    address public constant boldToken=address(0xb01d);
    uint256 public mode;
    function setMetadata(string memory n,string memory s) external {tokenName=n;tokenSymbol=s;}
    function name() external view returns(string memory) {require(mode!=5&&mode!=7,"name failed");return tokenName;}
    function symbol() external view returns(string memory) {require(mode!=6&&mode!=7,"symbol failed");return tokenSymbol;}
    function setMode(uint256 value) external {mode=value;}
    function getLatestTroveData(uint256 id) external view returns(LatestTroveData memory) {
        require(mode!=1,"latest failed");
        return LatestTroveData(id+1,id+2,id+3,id+4,id+5,id+6,id+7,id+8,id+9,id+10);
    }
    function getTroveStatus(uint256 id) external view returns(ITroveManager.Status) {
        require(mode!=2,"status failed");
        if(mode==4)assembly {mstore(0,5) return(0,32)}
        return ITroveManager.Status(id%5);
    }
    function uri(IMetadataNFT.TroveData memory data) external view returns(string memory) {
        require(mode!=3,"uri failed");
        return string(abi.encode(data));
    }
}
contract NFTReceiver {
    uint256 public mode; bytes32 public observed;
    function setMode(uint256 value) external {mode=value;}
    function onERC721Received(address operator,address from,uint256 id,bytes calldata data) external returns(bytes4) {
        TroveNFT token=TroveNFT(msg.sender);
        require(token.ownerOf(id)==address(this),"callback ownership");
        require(token.getApproved(id)==address(0),"callback approval");
        observed=keccak256(abi.encode(operator,from,id,data,token.balanceOf(address(this))));
        if(mode==1)return 0xffffffff;
        if(mode==2)revert("receiver failed");
        if(mode==3)assembly{revert(0,0)}
        if(mode==4)assembly{return(0,0)}
        if(mode==5)assembly{mstore(0,or(shl(224,0x150b7a02),1)) return(0,32)}
        if(mode==6)token.transferFrom(address(this),address(0xcafe),id);
        return this.onERC721Received.selector;
    }
}
contract TroveNFTParityTest {
    PoolVm constant vm=PoolVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    TroveNFT a;TroveNFT b;NFTDependencies deps;NFTReceiver receiver;
    address constant ALICE=address(0xa11ce);address constant BOB=address(0xb0b);address constant OP=address(0x1234);
    function deploy() internal {
        bytes memory code=bytes.concat(vm.parseBytes(vm.readFile("build/TroveNFT.bin")),abi.encode(deps));
        address created;assembly {created:=create(0,add(code,32),mload(code))}
        require(created.code.length>0,"Fe deployment");a=TroveNFT(created);b=new TroveNFT(IAddressesRegistry(address(deps)));
    }
    function setUp() public {deps=new NFTDependencies();receiver=new NFTReceiver();deploy();}
    function sameView(bytes memory data) internal view {
        (bool x,bytes memory p)=address(a).staticcall(data);(bool y,bytes memory q)=address(b).staticcall(data);
        require(x==y&&keccak256(p)==keccak256(q),"view mismatch");
    }
    function sameState() internal view {
        address[6] memory owners=[ALICE,BOB,OP,address(receiver),address(0xcafe),address(0)];
        for(uint256 id;id<8;id++) {
            sameView(abi.encodeCall(a.ownerOf,(id)));sameView(abi.encodeCall(a.getApproved,(id)));
            for(uint256 root=2;root<=4;root+=2)checkSlot(keccak256(abi.encode(id,root)));
        }
        for(uint256 i;i<owners.length;i++) {
            sameView(abi.encodeCall(a.balanceOf,(owners[i])));checkSlot(keccak256(abi.encode(owners[i],uint256(3))));
            for(uint256 j;j<owners.length;j++) {
                sameView(abi.encodeCall(a.isApprovedForAll,(owners[i],owners[j])));
                checkSlot(keccak256(abi.encode(owners[j],keccak256(abi.encode(owners[i],uint256(5))))));
            }
        }
    }
    function checkSlot(bytes32 slot) internal view {
        require(StorageVm(address(vm)).load(address(a),slot)==StorageVm(address(vm)).load(address(b),slot),"storage mismatch");
    }
    function compare(address caller,bytes memory data) internal returns(bool) {
        vm.recordLogs();vm.prank(caller);(bool x,bytes memory p)=address(a).call(data);PoolVm.Log[] memory logsA=vm.getRecordedLogs();bytes32 observedA=receiver.observed();
        vm.recordLogs();vm.prank(caller);(bool y,bytes memory q)=address(b).call(data);PoolVm.Log[] memory logsB=vm.getRecordedLogs();
        require(x==y,"success mismatch");require(keccak256(p)==keccak256(q),"return/revert mismatch");require(observedA==receiver.observed(),"receiver arguments");
        require(logsA.length==logsB.length,"event count");
        for(uint i;i<logsA.length;i++)require(keccak256(abi.encode(logsA[i].topics,logsA[i].data))==keccak256(abi.encode(logsB[i].topics,logsB[i].data)),"event mismatch");
        sameState();return x;
    }
    function mint(address owner,uint256 id) internal {require(compare(address(deps),abi.encodeCall(a.mint,(owner,id))),"mint failed");}
    function testMetadataAndInterfaces() public {
        sameView(abi.encodeCall(a.name,()));sameView(abi.encodeCall(a.symbol,()));sameView(abi.encodeCall(a.troveManager,()));sameView(abi.encodeCall(a.metadataNFT,()));
        bytes4[5] memory ids=[bytes4(0x80ac58cd),bytes4(0x5b5e139f),bytes4(0x01ffc9a7),bytes4(0xffffffff),bytes4(0)];
        for(uint i;i<ids.length;i++)sameView(abi.encodeCall(a.supportsInterface,(ids[i])));
        for(uint id;id<5;id++){mint(ALICE,id);sameView(abi.encodeCall(a.tokenURI,(id)));}
        sameView(abi.encodeCall(a.tokenURI,(uint256(7))));
        for(uint mode=1;mode<=4;mode++){deps.setMode(mode);sameView(abi.encodeCall(a.tokenURI,(uint256(0))));sameView(abi.encodeCall(a.tokenURI,(uint256(7))));}
    }
    function testFuzzConstructorStrings(string memory n,string memory s) public {
        NFTVm(address(vm)).assume(bytes(n).length<256&&bytes(s).length<256);deps.setMetadata(n,s);deploy();
        require(keccak256(bytes(a.name()))==keccak256(bytes(b.name())),"name");require(keccak256(bytes(a.symbol()))==keccak256(bytes(b.symbol())),"symbol");
        for(uint256 root;root<2;root++) {
            checkSlot(bytes32(root));bytes32 base=keccak256(abi.encode(root));
            for(uint i;i<9;i++)checkSlot(bytes32(uint256(base)+i));
        }
        deps.setMetadata("changed","CHG");sameView(abi.encodeCall(a.name,()));sameView(abi.encodeCall(a.symbol,()));
    }
    function testConstructorDependencyFailures() public {
        for(uint mode=5;mode<=7;mode++) {
            deps.setMode(mode);
            bytes memory code=bytes.concat(vm.parseBytes(vm.readFile("build/TroveNFT.bin")),abi.encode(deps));
            address created;bytes memory reason;
            assembly {
                created:=create(0,add(code,32),mload(code))
                reason:=mload(0x40)
                mstore(reason,returndatasize())
                returndatacopy(add(reason,32),0,returndatasize())
                mstore(0x40,add(add(reason,32),and(add(returndatasize(),31),not(31))))
            }
            require(created==address(0),"Fe constructor must fail");
            try new TroveNFT(IAddressesRegistry(address(deps))) {revert("Solidity constructor succeeded");}
            catch(bytes memory solReason){require(keccak256(reason)==keccak256(solReason),"constructor revert order");}
        }
    }
    function testApprovalsTransfersBurnAndRemint() public {
        mint(ALICE,1);mint(ALICE,2);
        require(compare(ALICE,abi.encodeCall(a.approve,(OP,uint256(1)))));
        require(compare(OP,abi.encodeCall(a.transferFrom,(ALICE,BOB,uint256(1)))));
        require(compare(BOB,abi.encodeCall(a.transferFrom,(BOB,BOB,uint256(1)))));
        require(compare(ALICE,abi.encodeCall(a.setApprovalForAll,(OP,true))));
        require(compare(OP,abi.encodeCall(a.approve,(BOB,uint256(2)))));
        require(compare(BOB,abi.encodeCall(a.transferFrom,(ALICE,BOB,uint256(2)))));
        require(compare(address(deps),abi.encodeCall(a.burn,(uint256(1)))));mint(OP,1);
        require(compare(ALICE,abi.encodeCall(a.setApprovalForAll,(OP,false))));
    }
    function testReceiverModesAndReentrancy() public {
        for(uint mode;mode<=6;mode++) {
            mint(ALICE,mode);receiver.setMode(mode);require(compare(ALICE,abi.encodeCall(a.approve,(OP,mode))));
            bool success=compare(OP,abi.encodeWithSignature("safeTransferFrom(address,address,uint256,bytes)",ALICE,address(receiver),mode,hex"0001020300ff"));
            require(success==(mode==0||mode==6),"receiver success");
        }
        mint(ALICE,7);require(compare(ALICE,abi.encodeWithSignature("safeTransferFrom(address,address,uint256)",ALICE,BOB,uint256(7))));
    }
    function testAuthorizationAndErrorOrder() public {
        compare(ALICE,abi.encodeCall(a.mint,(ALICE,uint256(1))));compare(ALICE,abi.encodeCall(a.burn,(uint256(1))));
        compare(address(deps),abi.encodeCall(a.mint,(address(0),uint256(1))));compare(address(deps),abi.encodeCall(a.burn,(uint256(1))));
        mint(ALICE,1);compare(address(deps),abi.encodeCall(a.mint,(BOB,uint256(1))));
        compare(ALICE,abi.encodeCall(a.approve,(ALICE,uint256(1))));compare(BOB,abi.encodeCall(a.approve,(OP,uint256(1))));
        compare(ALICE,abi.encodeCall(a.approve,(OP,uint256(7))));compare(ALICE,abi.encodeCall(a.setApprovalForAll,(ALICE,true)));
        compare(BOB,abi.encodeCall(a.transferFrom,(ALICE,BOB,uint256(1))));compare(ALICE,abi.encodeCall(a.transferFrom,(BOB,OP,uint256(1))));
        compare(ALICE,abi.encodeCall(a.transferFrom,(ALICE,address(0),uint256(1))));compare(ALICE,abi.encodeCall(a.transferFrom,(ALICE,BOB,uint256(7))));
        compare(ALICE,abi.encodeWithSignature("safeTransferFrom(address,address,uint256)",ALICE,address(deps),uint256(1)));
    }
    function testAbiValidationAndUnpaddedBytes() public {
        mint(ALICE,1);
        compare(ALICE,hex"ffffffff");compare(ALICE,hex"23b872dd");
        compare(ALICE,bytes.concat(a.approve.selector,abi.encode(type(uint256).max,uint256(1))));
        compare(ALICE,bytes.concat(a.setApprovalForAll.selector,abi.encode(OP,uint256(2))));
        sameView(bytes.concat(a.supportsInterface.selector,abi.encode(uint256(0x80ac58cd)<<224|1)));
        bytes memory data=abi.encodeWithSignature("safeTransferFrom(address,address,uint256,bytes)",ALICE,BOB,uint256(1),hex"ff");
        assembly {mstore(data,sub(mload(data),31))}
        require(compare(ALICE,data),"unpadded dynamic bytes");
    }
    function testFuzzLifecycle(uint256 seed) public {
        address[3] memory users=[ALICE,BOB,OP];
        for(uint step;step<20;step++) {
            seed=uint256(keccak256(abi.encode(seed,step)));uint256 id=seed%8;uint256 op=(seed>>8)%6;
            address caller=users[(seed>>16)%3];address to=users[(seed>>24)%3];bytes memory data;
            if(op==0){caller=address(deps);data=abi.encodeCall(a.mint,(to,id));}
            else if(op==1){caller=address(deps);data=abi.encodeCall(a.burn,(id));}
            else if(op==2)data=abi.encodeCall(a.approve,(to,id));
            else if(op==3)data=abi.encodeCall(a.setApprovalForAll,(to,(seed>>32)%2==1));
            else if(op==4)data=abi.encodeCall(a.transferFrom,(users[(seed>>40)%3],to,id));
            else data=abi.encodeWithSignature("safeTransferFrom(address,address,uint256)",users[(seed>>40)%3],to,id);
            compare(caller,data);
            uint256 count;
            for(uint256 tokenId;tokenId<8;tokenId++){try a.ownerOf(tokenId) returns(address){count++;}catch{}}
            require(count==a.balanceOf(ALICE)+a.balanceOf(BOB)+a.balanceOf(OP),"ownership conservation");
        }
    }
}
