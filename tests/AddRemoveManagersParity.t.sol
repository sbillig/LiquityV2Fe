// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {AddRemoveManagers, IAddressesRegistry} from "../reference/bold/contracts/src/Dependencies/AddRemoveManagers.sol";
import {PoolVm} from "./DefaultPoolParity.t.sol";
interface ManagerEnvVm {function envOr(string calldata,string calldata) external returns(string memory);}
contract ManagerNFTMock {
    mapping(uint256=>address) public owners;
    address public immutable troveNFT=address(this);
    function setOwner(uint256 id,address value) external {owners[id]=value;}
    function ownerOf(uint256 id) external view returns(address) {require(owners[id]!=address(0),"ERC721: invalid token ID");return owners[id];}
}
contract ManagerReferenceHarness is AddRemoveManagers {
    constructor(IAddressesRegistry registry) AddRemoveManagers(registry) {}
    function setInternal(uint256 id,address add,address remove,address receiver) external {_setAddManager(id,add);_setRemoveManagerAndReceiver(id,remove,receiver);}
    function wipe(uint256 id) external {_wipeAddRemoveManagers(id);}
    function checkAdd(uint256 id,address owner) external view {_requireSenderIsOwnerOrAddManager(id,owner);}
    function checkRemove(uint256 id,address owner) external view returns(address){return _requireSenderIsOwnerOrRemoveManagerAndGetReceiver(id,owner);}
}
contract AddRemoveManagersParityTest {
    PoolVm constant vm=PoolVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    ManagerNFTMock nft;AddRemoveManagers a;AddRemoveManagers b;ManagerReferenceHarness ha;ManagerReferenceHarness hb;
    address constant ALICE=address(0xa11ce);address constant BOB=address(0xb0b);address constant OTHER=address(0xbeef);
    function feDeploy(string memory name,bytes memory args) internal returns(address created) {
        bytes memory code=bytes.concat(vm.parseBytes(vm.readFile(string.concat(ManagerEnvVm(address(vm)).envOr("LIQUITY_TEST_ARTIFACTS","build"),"/",name,".bin"))),args);
        assembly{created:=create(0,add(code,32),mload(code))}require(created.code.length>0,"Fe deployment");
    }
    function setUp() public {
        nft=new ManagerNFTMock();nft.setOwner(1,ALICE);
        vm.recordLogs();a=AddRemoveManagers(feDeploy("AddRemoveManagers",abi.encode(nft)));PoolVm.Log[] memory x=vm.getRecordedLogs();
        vm.recordLogs();b=new AddRemoveManagers(IAddressesRegistry(address(nft)));equalLogs(x,vm.getRecordedLogs());
        ha=ManagerReferenceHarness(feDeploy("ManagerHarness",hex""));hb=new ManagerReferenceHarness(IAddressesRegistry(address(nft)));
    }
    function equalLogs(PoolVm.Log[] memory x,PoolVm.Log[] memory y) internal pure {
        require(x.length==y.length,"event count");for(uint i;i<x.length;i++)require(keccak256(abi.encode(x[i].topics,x[i].data))==keccak256(abi.encode(y[i].topics,y[i].data)),"events");
    }
    function compare(address x,address y,address caller,bytes memory data) internal returns(bool) {
        vm.recordLogs();vm.prank(caller);(bool okA,bytes memory p)=x.call(data);PoolVm.Log[] memory logsA=vm.getRecordedLogs();
        vm.recordLogs();vm.prank(caller);(bool okB,bytes memory q)=y.call(data);equalLogs(logsA,vm.getRecordedLogs());
        require(okA==okB&&keccak256(p)==keccak256(q),"outcome");return okA;
    }
    function compareBase(address caller,bytes memory data) internal returns(bool) {return compare(address(a),address(b),caller,data);}
    function compareHarness(address caller,bytes memory data) internal returns(bool) {return compare(address(ha),address(hb),caller,data);}
    function sameState(uint256 id) internal view {
        require(a.addManagerOf(id)==b.addManagerOf(id));(address ma,address ra)=a.removeManagerReceiverOf(id);(address mb,address rb)=b.removeManagerReceiverOf(id);require(ma==mb&&ra==rb);
    }
    function testPublicSettersAndOwnershipTransfer() public {
        require(compareBase(ALICE,abi.encodeCall(a.setAddManager,(1,BOB))));
        require(compareBase(ALICE,abi.encodeCall(a.setRemoveManager,(1,BOB))));sameState(1);
        require(!compareBase(BOB,abi.encodeCall(a.setAddManager,(1,OTHER))));
        nft.setOwner(1,BOB);require(!compareBase(ALICE,abi.encodeCall(a.setRemoveManager,(1,OTHER))));
        require(compareBase(BOB,abi.encodeCall(a.setRemoveManagerWithReceiver,(1,ALICE,OTHER))));sameState(1);
        require(!compareBase(BOB,abi.encodeCall(a.setRemoveManager,(1,address(0)))));
        require(compareBase(BOB,abi.encodeCall(a.setRemoveManagerWithReceiver,(1,address(0),address(0)))));sameState(1);
    }
    function testErrorsAndMissingNFT() public {
        require(!compareBase(ALICE,abi.encodeCall(a.setAddManager,(9,BOB))));
        require(!compareBase(ALICE,abi.encodeCall(a.setRemoveManager,(9,BOB))));
        require(!compareBase(BOB,abi.encodeCall(a.setRemoveManagerWithReceiver,(1,address(0),OTHER))));
        require(!compareBase(ALICE,abi.encodeCall(a.setRemoveManagerWithReceiver,(1,address(0),OTHER))));sameState(1);
    }
    function testPermissionMatrixAndWipe() public {
        address[4] memory actors=[address(0),ALICE,BOB,OTHER];
        for(uint i;i<4;i++)for(uint j;j<4;j++)for(uint k;k<4;k++) {
            bool configured=compareHarness(ALICE,abi.encodeCall(ha.setInternal,(1,actors[i],actors[j],actors[k])));
            require(configured==(j!=0||k==0));if(!configured)continue;
            for(uint c;c<4;c++) {
                bool addOk=compareHarness(actors[c],abi.encodeCall(ha.checkAdd,(1,ALICE)));
                require(addOk==(actors[c]==ALICE||actors[i]==address(0)||actors[c]==actors[i]||actors[c]==actors[j]));
                bool removeOk=compareHarness(actors[c],abi.encodeCall(ha.checkRemove,(1,ALICE)));
                require(removeOk==(actors[c]==ALICE||actors[c]==actors[j]));
            }
            require(compareHarness(ALICE,abi.encodeCall(ha.wipe,(1))));require(ha.addManagerOf(1)==address(0));(address manager,address receiver)=ha.removeManagerReceiverOf(1);require(manager==address(0)&&receiver==address(0));
        }
    }
    function testFuzzConfiguration(uint256 id,address owner,address manager,address receiver) public {
        if(owner==address(0))owner=ALICE;nft.setOwner(id,owner);
        require(compareBase(owner,abi.encodeCall(a.setAddManager,(id,manager))));
        bool success=compareBase(owner,abi.encodeCall(a.setRemoveManagerWithReceiver,(id,manager,receiver)));
        require(success==(manager!=address(0)||receiver==address(0)));sameState(id);
    }
}
