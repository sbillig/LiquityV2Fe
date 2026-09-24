// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {UserProxy} from "../reference/bold/contracts/lib/V2-gov/src/UserProxy.sol";
import {PermitParams} from "../reference/bold/contracts/lib/V2-gov/src/utils/Types.sol";
import {UserProxyFactory} from "../reference/bold/contracts/lib/V2-gov/src/UserProxyFactory.sol";
interface UPVm {
 function readFile(string calldata) external view returns(string memory);
 function parseBytes(string calldata) external pure returns(bytes memory);
 function prank(address) external;
 function deal(address,uint) external;
}
contract UPToken {
 mapping(address=>uint) public balanceOf;
 bool public permitFails;uint public mode;
 function setMode(uint n) external {mode=n;}
 function reply() internal view returns(bool){if(mode==2){assembly{return(0,0)}}return mode!=1;}
 function mint(address a,uint n) external {balanceOf[a]+=n;}
 function move(address a,address b,uint n) public {balanceOf[a]-=n;balanceOf[b]+=n;}
 function transfer(address a,uint n) external returns(bool){move(msg.sender,a,n);return reply();}
 function transferFrom(address a,address b,uint n) external returns(bool){move(a,b,n);return reply();}
 function setPermitFails(bool b) external {permitFails=b;}
 function permit(address,address,uint,uint,uint8,bytes32,bytes32) external view {require(!permitFails,"permit failure");}
}
contract UPStaking {
 UPToken public lqty;UPToken public lusd;mapping(address=>uint) public stakes;
 constructor(UPToken a,UPToken b){lqty=a;lusd=b;}
 function rewards() internal {lusd.mint(msg.sender,7);(bool ok,)=msg.sender.call{value:3}("");require(ok);}
 function stake(uint n) external {lqty.move(msg.sender,address(this),n);stakes[msg.sender]+=n;rewards();}
 function unstake(uint n) external {if(n>stakes[msg.sender])n=stakes[msg.sender];stakes[msg.sender]-=n;lqty.move(address(this),msg.sender,n);rewards();}
}
contract UPReject {receive() external payable {revert("no ETH");}}
contract UserProxyParityTest {
 UPVm constant vm=UPVm(address(uint160(uint(keccak256("hevm cheat code")))));
 receive() external payable {}
 function make(bool fe,bool isFactory) internal returns(address a,UPToken lqty,UPToken lusd,UPStaking staking){
  lqty=new UPToken();lusd=new UPToken();staking=new UPStaking(lqty,lusd);vm.deal(address(staking),1e24);
  bytes memory code=fe?vm.parseBytes(vm.readFile(isFactory?"build/UserProxyFactory.bin":"build/UserProxy.bin")):(isFactory?type(UserProxyFactory).creationCode:type(UserProxy).creationCode);
  bytes memory init=bytes.concat(code,abi.encode(lqty,lusd,staking));assembly{a:=create(0,add(init,32),mload(init))}require(a.code.length>0&&a.code.length<=24576,"deployment");
 }
 function run(bool fe,uint amount,bool send) internal returns(bytes32){
  (address a,UPToken lqty,UPToken lusd,UPStaking staking)=make(fe,false);UserProxy p=UserProxy(payable(a));
  require(address(p.lqty())==address(lqty)&&address(p.lusd())==address(lusd)&&address(p.stakingV1())==address(staking)&&p.stakingV2()==address(this),"configuration");
  lqty.mint(address(this),amount);lusd.mint(a,11);vm.deal(a,13);vm.deal(address(0x1234),0);
  {
   (uint lr,uint ls,uint er,uint es)=p.stake(amount,address(this),send,address(0x1234));
   require(lr==7&&er==3&&ls==(send?18:0)&&es==(send?16:0),"stake rewards");require(p.staked()==amount,"stake");
  }
  lqty.mint(a,19);
  (bool ok,bytes memory result)=a.call(abi.encodeWithSignature("unstake(uint256,bool,address)",type(uint).max,true,address(0x1234)));
  require(ok&&keccak256(result)==keccak256(abi.encode(amount,amount+19,uint(7),send?7:25,uint(3),send?3:19)),"unstake accounting");
  require(p.staked()==0&&lqty.balanceOf(a)==0&&lusd.balanceOf(a)==0&&a.balance==0,"sweep");
  return keccak256(abi.encode(lqty.balanceOf(address(0x1234)),lusd.balanceOf(address(0x1234)),address(0x1234).balance));
 }
 function testFuzzStakeUnstakeRewards(uint96 amount,bool send) public {require(run(true,amount,send)==run(false,amount,send),"parity");}
 function factory(bool fe,address user) internal {
  (address a,UPToken lqty,UPToken lusd,UPStaking staking)=make(fe,true);UserProxyFactory f=UserProxyFactory(a);address clone;
  { address impl=f.userProxyImplementation();
  bytes memory runtime=abi.encodePacked(hex"363d3d373d3d3d363d73",impl,hex"5af43d82803e903d91602b57fd5bf3");
  bytes32 digest=keccak256(abi.encodePacked(bytes1(0xff),a,bytes32(uint(uint160(user))),keccak256(abi.encodePacked(hex"3d602d80600a3d3981f3",runtime))));
  address predicted=address(uint160(uint(digest)));require(f.deriveUserProxyAddress(user)==predicted,"prediction");
  vm.prank(user);clone=f.deployUserProxy();require(clone==predicted&&keccak256(clone.code)==keccak256(runtime),"clone runtime");
  }
  UserProxy p=UserProxy(payable(clone));require(address(p.lqty())==address(lqty)&&address(p.lusd())==address(lusd)&&address(p.stakingV1())==address(staking)&&p.stakingV2()==a,"clone immutable configuration");
  lqty.mint(user,100);vm.prank(a);p.stake(100,user,false,user);require(p.staked()==100,"clone stake");
  vm.prank(user);(bool ok,bytes memory data)=a.call(abi.encodeWithSignature("deployUserProxy()"));require(!ok&&keccak256(data)==keccak256(abi.encodeWithSignature("ERC1167FailedCreateClone()")),"duplicate");
 }
 function testFuzzFactoryDeterministicClones(address user) public {factory(true,user);factory(false,user);}
 function compare(address a,address b,bytes memory data,address caller) internal returns(bool){
  vm.prank(caller);(bool ok,bytes memory x)=a.call(data);
  vm.prank(caller);(bool success,bytes memory y)=b.call(data);
  require(ok==success&&keccak256(x)==keccak256(y),"call parity");return ok;
 }
 function permitData() internal view returns(bytes memory){return abi.encodeWithSignature("stakeViaPermit(uint256,address,(address,address,uint256,uint256,uint8,bytes32,bytes32),bool,address)",uint(0),address(this),PermitParams(address(this),address(0),0,0,27,bytes32(0),bytes32(0)),false,address(this));}
 function testPermitFailureIgnoredAndLazyValidation() public {
  (address a,UPToken ta,,)=make(true,false);(address b,UPToken tb,,)=make(false,false);
  ta.setPermitFails(true);tb.setPermitFails(true);
  bytes memory data=permitData();require(compare(a,b,data,address(this)),"permit failure caught");
  for(uint word;word<7;word++) {
   data=permitData();uint value=type(uint).max;
   assembly{mstore(add(add(data,100),mul(word,32)),value)}
   require(!compare(a,b,data,address(0x9999)),"unauthorized");
   bool ok=compare(a,b,data,address(this));
   require(ok==(word==2||word==3||word==5||word==6),"lazy canonical fields");
  }
  data=permitData();assembly{mstore(add(data,100),123)}
  require(!compare(a,b,data,address(this)),"owner mismatch");
 }
 function testReceiveAndDispatch() public {
  (address a,,,)=make(true,false);(address b,,,)=make(false,false);
  require(compare(a,b,hex"",address(this)),"receive");
  require(!compare(a,b,hex"01",address(this)),"fallback");
  require(!compare(a,b,abi.encodeWithSignature("stake(uint256,address,bool,address)",0,address(this),false,address(this)),address(77)),"authorization");
 }

 function failureRun(bool fe,uint mode,bool reject) internal returns(bytes32){
  (address a,UPToken lqty,UPToken lusd,UPStaking staking)=make(fe,false);
  lqty.setMode(mode);lusd.setMode(mode);lqty.mint(address(this),100);
  address recipient=reject?address(new UPReject()):address(1234);vm.deal(recipient,0);
  (bool ok,bytes memory data)=a.call(abi.encodeWithSignature("stake(uint256,address,bool,address)",uint(100),address(this),true,recipient));
  require(ok==(mode!=2&&!reject),"expected outcome");
  if(!ok)require(lqty.balanceOf(a)==0&&lusd.balanceOf(a)==0&&staking.stakes(a)==0&&a.balance==0,"atomic rollback");
  return keccak256(abi.encode(ok,data,lqty.balanceOf(a),lusd.balanceOf(a),staking.stakes(a),a.balance));
 }
 function testTokenReturnRulesAndRewardFailureRollback() public {
  for(uint mode;mode<3;mode++)for(uint reject;reject<2;reject++)require(failureRun(true,mode,reject==1)==failureRun(false,mode,reject==1),"failure parity");
 }

}
