// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {LiquityMath} from "../reference/bold/contracts/src/Dependencies/LiquityMath.sol";
import {ONE_YEAR, DECIMAL_PRECISION} from "../reference/bold/contracts/src/Dependencies/Constants.sol";
interface Vm {
    function readFile(string calldata) external view returns (string memory);
    function parseBytes(string calldata) external pure returns (bytes memory);
}
contract SolidityMath {
    function min(uint256 a,uint256 b) external pure returns(uint256) { return LiquityMath._min(a,b); }
    function max(uint256 a,uint256 b) external pure returns(uint256) { return LiquityMath._max(a,b); }
    function subMinZero(uint256 a,uint256 b) external pure returns(uint256) { return LiquityMath._sub_min_0(a,b); }
    function absoluteDifference(uint256 a,uint256 b) external pure returns(uint256) { return LiquityMath._getAbsoluteDifference(a,b); }
    function decMul(uint256 a,uint256 b) external pure returns(uint256) { return LiquityMath.decMul(a,b); }
    function decPow(uint256 a,uint256 b) external pure returns(uint256) { return LiquityMath._decPow(a,b); }
    function computeCR(uint256 a,uint256 b,uint256 c) external pure returns(uint256) { return LiquityMath._computeCR(a,b,c); }
    function calcInterest(uint256 a,uint256 b) external pure returns(uint256) { return a*b/ONE_YEAR/DECIMAL_PRECISION; }
}
contract MathParityTest {
    Vm constant vm=Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address fe;
    SolidityMath ref;
    function setUp() public {
        bytes memory code=vm.parseBytes(vm.readFile("build/MathHarness.bin"));
        address deployed;
        assembly { deployed := create(0,add(code,32),mload(code)) }
        require(deployed.code.length>0,"Fe deployment failed");
        fe=deployed;
        ref=new SolidityMath();
    }
    function parity(bytes memory data) internal view {
        (bool a,bytes memory x)=fe.staticcall(data);
        (bool b,bytes memory y)=address(ref).staticcall(data);
        require(a==b,"success mismatch");
        require(keccak256(x)==keccak256(y),"return/revert data mismatch");
    }
    function testFuzzBasic(uint256 a,uint256 b) public view {
        parity(abi.encodeCall(ref.min,(a,b)));
        parity(abi.encodeCall(ref.max,(a,b)));
        parity(abi.encodeCall(ref.subMinZero,(a,b)));
        parity(abi.encodeCall(ref.absoluteDifference,(a,b)));
    }
    function testFuzzMul(uint256 a,uint256 b) public view { parity(abi.encodeCall(ref.decMul,(a,b))); }
    function testFuzzMulBounded(uint128 a,uint128 b) public view { parity(abi.encodeCall(ref.decMul,(a,b))); }
    function testFuzzPow(uint256 base,uint256 exponent) public view { parity(abi.encodeCall(ref.decPow,(base,exponent))); }
    function testFuzzDecay(uint256 base,uint256 exponent) public view { parity(abi.encodeCall(ref.decPow,(base%1e18,exponent))); }
    function testFuzzCR(uint256 coll,uint256 debt,uint256 price) public view { parity(abi.encodeCall(ref.computeCR,(coll,debt,price))); }
    function testFuzzCRBounded(uint128 coll,uint256 debt,uint128 price) public view { parity(abi.encodeCall(ref.computeCR,(coll,debt,price))); }
    function testFuzzInterest(uint256 debt,uint256 period) public view { parity(abi.encodeCall(ref.calcInterest,(debt,period))); }
    function testFuzzInterestBounded(uint128 debt,uint64 period) public view { parity(abi.encodeCall(ref.calcInterest,(debt,period))); }
    function testBoundaries() public view {
        parity(abi.encodeCall(ref.decMul,(uint256(1),uint256(5e17))));
        parity(abi.encodeCall(ref.decMul,(uint256(1),uint256(5e17-1))));
        parity(abi.encodeCall(ref.decMul,(type(uint256).max,uint256(1))));
        parity(abi.encodeCall(ref.computeCR,(type(uint256).max,uint256(0),type(uint256).max)));
        parity(abi.encodeCall(ref.decPow,(uint256(998076443575628800),uint256(360))));
        parity(abi.encodeCall(ref.decPow,(uint256(998076443575628800),uint256(525600001))));
        parity(abi.encodeCall(ref.decPow,(type(uint256).max,uint256(0))));
    }
}
