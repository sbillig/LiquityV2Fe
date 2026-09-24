// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {IERC20,SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {UPVm} from "./UserProxyParity.t.sol";
contract GovTokenReference {
 using SafeERC20 for IERC20;
 function transfer(address token,address to,uint amount) external {IERC20(token).safeTransfer(to,amount);}
 function transferFrom(address token,address from,address to,uint amount) external {IERC20(token).safeTransferFrom(from,to,amount);}
}
contract GovRawToken {
 bytes public data;bool public fail;uint public calls;
 function configure(bytes calldata d,bool f) external {data=d;fail=f;calls=0;}
 fallback() external {calls++;bytes memory d=data;bool f=fail;assembly{if f{revert(add(d,32),mload(d))}return(add(d,32),mload(d))}}
}
contract GovernanceTokenParityTest {
 UPVm constant vm=UPVm(address(uint160(uint(keccak256("hevm cheat code")))));
 address fe;address sol;GovRawToken token;
 function setUp() public {bytes memory code=vm.parseBytes(vm.readFile("build/GovernanceTokenHarness.bin"));address a;assembly{a:=create(0,add(code,32),mload(code))}require(a.code.length>0);fe=a;sol=address(new GovTokenReference());token=new GovRawToken();}
 function compare(bytes memory data) internal returns(bool){uint beforeCount=token.calls();(bool ok,bytes memory a)=fe.call(data);uint feCount=token.calls()-beforeCount;(bool success,bytes memory b)=sol.call(data);require(ok==success&&keccak256(a)==keccak256(b),"token parity");require(token.calls()-beforeCount==2*feCount,"rollback parity");return ok;}
 function run(bytes memory result,bool fail) internal {
  token.configure(result,fail);
  compare(abi.encodeWithSignature("transfer(address,address,uint256)",address(token),address(123),uint(7)));
  compare(abi.encodeWithSignature("transferFrom(address,address,address,uint256)",address(token),address(456),address(123),uint(7)));
 }
 function testFuzzTokenReturndata(bytes memory result,bool fail) public {run(result,fail);}
 function testOptionalBoolAndMalformedReturn() public {
  for(uint n;n<3;n++)for(uint fail;fail<2;fail++)run(abi.encode(n),fail==1);
  run(hex"",false);run(hex"",true);run(abi.encodeWithSignature("Error(string)","token failed"),true);
  for(uint n=1;n<32;n++)run(new bytes(n),false);
  run(bytes.concat(abi.encode(uint(1)),hex"abcd"),false);
 }
 function testMissingCode() public {require(!compare(abi.encodeWithSignature("transfer(address,address,uint256)",address(999),address(123),uint(7))));}
}
