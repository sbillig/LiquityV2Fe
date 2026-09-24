// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {safeCallWithMinGas} from "../reference/bold/contracts/lib/V2-gov/src/utils/SafeCallMinGas.sol";
import {GSVm} from "./GovernanceSnapshotParity.t.sol";
contract GovHooksReference {
 function run(address target,uint gasAmount,uint value,bytes memory data) external returns(bool){return safeCallWithMinGas(target,gasAmount,value,data);}
}
contract GovHookTarget {
 uint public calls;uint public mode;
 function setMode(uint m) external {mode=m;}
 fallback() external payable {
  calls++;uint m=mode;
  if(m==1)revert("hook failure");
  if(m==2)assembly{invalid()}
  if(m==3)assembly{return(0,131072)}
 }
}
contract GovernanceHooksParityTest {
 GSVm constant vm=GSVm(address(uint160(uint(keccak256("hevm cheat code")))));
 address fe;address sol;GovHookTarget target;
 function setUp() public {bytes memory code=vm.parseBytes(vm.readFile("build/GovernanceHooksHarness.bin"));address a;assembly{a:=create(0,add(code,32),mload(code))}require(a.code.length>0);fe=a;sol=address(new GovHooksReference());target=new GovHookTarget();vm.deal(fe,100);vm.deal(sol,100);}
 function compare(uint budget,uint supplied,uint value,bytes memory payload,address recipient) internal returns(bool){
  bytes memory data=abi.encodeWithSignature("run(address,uint256,uint256,bytes)",recipient,supplied,value,payload);
  (bool ok,bytes memory a)=fe.call{gas:budget}(data);(bool success,bytes memory b)=sol.call{gas:budget}(data);
  require(ok==success&&keccak256(a)==keccak256(b),"hook parity");return ok;
 }
 function testHookOutcomesAndReturnBomb() public {
  for(uint mode;mode<4;mode++){target.setMode(mode);uint beforeCalls=target.calls();require(compare(600000,350000,1,hex"abcdef",address(target)));require(target.calls()-beforeCalls==(mode==0||mode==3?2:0),"callee rollback");}
  require(compare(600000,350000,0,hex"",address(123)),"missing code allowed");
  require(compare(600000,350000,1000,hex"",address(target)),"insufficient ETH returns false");
 }
 function testGasReservationAndUncheckedMultiplication() public {
  require(!compare(100000,350000,0,hex"",address(target)),"minimum gas enforced");
  require(compare(600000,uint(1)<<250,0,hex"",address(target)),"reference arithmetic wraps");
 }
}
