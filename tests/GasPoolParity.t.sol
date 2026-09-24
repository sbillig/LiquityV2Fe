// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {GasPool} from "../reference/bold/contracts/src/GasPool.sol";
interface GasVm {
    function readFile(string calldata) external view returns (string memory);
    function parseBytes(string calldata) external pure returns (bytes memory);
}
contract ApprovalToken {
    uint256 public mode;
    mapping(address=>mapping(address=>uint256)) public allowance;
    mapping(address=>uint256) public count;
    constructor(uint256 m) { mode=m; }
    function approve(address spender,uint256 amount) external returns(bool) {
        allowance[msg.sender][spender]=amount;count[msg.sender]++;
        if(mode==2) { assembly { return(0,0) } }
        if(mode==3) revert("approval failed");
        if(mode==4) { assembly { mstore(0,2) return(0,32) } }
        return mode!=1;
    }
}
contract GasRegistryMock {
    address public WETH;
    address public borrowerOperations;
    address public troveManager;
    constructor(address t,address b,address m) { WETH=t;borrowerOperations=b;troveManager=m; }
}
contract GasPoolParityTest {
    GasVm constant vm=GasVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    function deploy(bytes memory code,address registry) internal returns(address deployed,bytes memory error) {
        bytes memory input=bytes.concat(code,abi.encode(registry));
        assembly {
            deployed := create(0,add(input,32),mload(input))
            let n := returndatasize()
            error := mload(0x40)
            mstore(error,n)
            returndatacopy(add(error,32),0,n)
            mstore(0x40,and(add(add(error,63),n),not(31)))
        }
    }
    function check(address token,address bo,address tm,bool succeeds) internal {
        GasRegistryMock registry=new GasRegistryMock(token,bo,tm);
        (address a,bytes memory x)=deploy(vm.parseBytes(vm.readFile("build/GasPool.bin")),address(registry));
        (address b,bytes memory y)=deploy(type(GasPool).creationCode,address(registry));
        require((a!=address(0))==succeeds,"Fe constructor");
        require((b!=address(0))==succeeds,"Solidity constructor");
        if(succeeds) {
            require(ApprovalToken(token).allowance(a,bo)==type(uint256).max,"BO allowance");
            require(ApprovalToken(token).allowance(a,tm)==type(uint256).max,"TM allowance");
            require(ApprovalToken(token).count(a)==2,"Fe call count");
            require(ApprovalToken(token).allowance(a,bo)==ApprovalToken(token).allowance(b,bo),"BO parity");
            require(ApprovalToken(token).allowance(a,tm)==ApprovalToken(token).allowance(b,tm),"TM parity");
            require(ApprovalToken(token).count(a)==ApprovalToken(token).count(b),"call count parity");
        } else require(keccak256(x)==keccak256(y),"constructor revert data");
    }
    function testFuzzApprovals(address bo,address tm) public { check(address(new ApprovalToken(0)),bo,tm,true); }
    function testFalseApprovalAcceptedLikeReference() public { check(address(new ApprovalToken(1)),address(1),address(2),true); }
    function testEmptyApprovalReturnRejected() public { check(address(new ApprovalToken(2)),address(1),address(2),false); }
    function testApprovalRevertBubbled() public { check(address(new ApprovalToken(3)),address(1),address(2),false); }
    function testInvalidBoolRejected() public { check(address(new ApprovalToken(4)),address(1),address(2),false); }
    function testCodelessTokenRejected() public { check(address(123),address(1),address(2),false); }
}
