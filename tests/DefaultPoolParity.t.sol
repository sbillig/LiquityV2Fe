// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {DefaultPool} from "../reference/bold/contracts/src/DefaultPool.sol";
import {IAddressesRegistry} from "../reference/bold/contracts/src/Interfaces/IAddressesRegistry.sol";
interface PoolVm {
    struct Log { bytes32[] topics; bytes data; address emitter; }
    function readFile(string calldata) external view returns(string memory);
    function parseBytes(string calldata) external pure returns(bytes memory);
    function prank(address) external;
    function recordLogs() external;
    function getRecordedLogs() external returns(Log[] memory);
    function etch(address,bytes calldata) external;
}
contract PoolToken {
    uint256 public mode;
    mapping(address=>uint256) public balanceOf;
    mapping(address=>mapping(address=>uint256)) public allowance;
    function setMode(uint256 m) external {mode=m;}
    function mint(address to,uint256 n) external {balanceOf[to]+=n;}
    function approve(address to,uint256 n) external returns(bool) {allowance[msg.sender][to]=n;return true;}
    function transferFrom(address from,address to,uint256 n) external returns(bool) {
        allowance[from][msg.sender]-=n;balanceOf[from]-=n;balanceOf[to]+=n;
        if(mode==1) return false;
        if(mode==2) {assembly {return(0,0)}}
        if(mode==3) revert("token reverted");
        if(mode==4) {assembly {revert(0,0)}}
        if(mode==5) {assembly {mstore(0,2) return(0,32)}}
        if(mode==6) {assembly {mstore(0,1) return(0,31)}}
        if(mode==7) {assembly {mstore(0,1) mstore(32,42) return(0,64)}}
        return true;
    }
}
contract ActivePoolMock {
    PoolToken token;
    mapping(address=>uint256) public received;
    constructor(PoolToken t){token=t;}
    function approve(address to,uint256 n) external {token.approve(to,n);}
    function receiveColl(uint256 n) external {received[msg.sender]+=n;require(token.transferFrom(msg.sender,address(this),n));}
}
contract DefaultRegistryMock {
    address public collToken;
    address public troveManager;
    address public activePool;
    constructor(address t,address m,address a){collToken=t;troveManager=m;activePool=a;}
}
contract DefaultPoolParityTest {
    PoolVm constant vm=PoolVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    PoolToken token;
    ActivePoolMock active;
    address a;
    address b;
    function setUp() public {
        token=new PoolToken();active=new ActivePoolMock(token);
        DefaultRegistryMock reg=new DefaultRegistryMock(address(token),address(this),address(active));
        bytes memory code=bytes.concat(vm.parseBytes(vm.readFile("build/DefaultPool.bin")),abi.encode(reg));
        vm.recordLogs();
        address deployed;assembly {deployed:=create(0,add(code,32),mload(code))}
        a=deployed;require(a.code.length>0);
        PoolVm.Log[] memory logs=vm.getRecordedLogs();
        vm.recordLogs();b=address(new DefaultPool(IAddressesRegistry(address(reg))));
        logsEqual(logs,vm.getRecordedLogs());
        active.approve(a,type(uint256).max);active.approve(b,type(uint256).max);
    }
    function logsEqual(PoolVm.Log[] memory x,PoolVm.Log[] memory y) internal pure {
        require(x.length==y.length,"log count");
        for(uint i;i<x.length;i++) {
            require(keccak256(abi.encode(x[i].topics))==keccak256(abi.encode(y[i].topics)),"topics");
            require(keccak256(x[i].data)==keccak256(y[i].data),"log data");
        }
    }
    function compare(address caller,bytes memory data) internal {
        vm.recordLogs();vm.prank(caller);(bool x,bytes memory rx)=a.call(data);
        PoolVm.Log[] memory logs=vm.getRecordedLogs();
        vm.recordLogs();vm.prank(caller);(bool y,bytes memory ry)=b.call(data);
        logsEqual(logs,vm.getRecordedLogs());
        require(x==y,"success");require(keccak256(rx)==keccak256(ry),"result");
        require(DefaultPool(a).getBoldDebt()==DefaultPool(b).getBoldDebt(),"debt");
        require(DefaultPool(a).getCollBalance()==DefaultPool(b).getCollBalance(),"collateral");
        if(address(token).code.length>0) require(token.balanceOf(a)==token.balanceOf(b),"token balance");
        if(address(active).code.length>0) require(active.received(a)==active.received(b),"active collateral");
    }
    function testGetters() public {
        compare(address(this),abi.encodeWithSignature("NAME()"));
        compare(address(this),abi.encodeWithSignature("collToken()"));
        compare(address(this),abi.encodeWithSignature("troveManagerAddress()"));
        compare(address(this),abi.encodeWithSignature("activePoolAddress()"));
        compare(address(this),abi.encodeWithSignature("getCollBalance()"));
        compare(address(this),abi.encodeWithSignature("getBoldDebt()"));
        require(token.allowance(a,address(active))==type(uint256).max,"allowance");
    }
    function testFuzzDebt(uint256 increase,uint256 decrease) public {
        compare(address(this),abi.encodeWithSignature("increaseBoldDebt(uint256)",increase));
        compare(address(this),abi.encodeWithSignature("increaseBoldDebt(uint256)",decrease));
        compare(address(this),abi.encodeWithSignature("decreaseBoldDebt(uint256)",decrease));
        compare(address(this),abi.encodeWithSignature("decreaseBoldDebt(uint256)",increase));
    }
    function testFuzzCollateral(uint128 amount,uint128 outgoing) public {
        token.mint(address(active),uint256(amount)*2);
        compare(address(active),abi.encodeWithSignature("receiveColl(uint256)",amount));
        compare(address(this),abi.encodeWithSignature("sendCollToActivePool(uint256)",outgoing));
    }
    function testFuzzUnauthorized(address caller,uint256 amount) public {
        if(caller==address(this)||caller==address(active)) return;
        compare(caller,abi.encodeWithSignature("receiveColl(uint256)",amount));
        compare(caller,abi.encodeWithSignature("sendCollToActivePool(uint256)",amount));
        compare(caller,abi.encodeWithSignature("increaseBoldDebt(uint256)",amount));
        compare(caller,abi.encodeWithSignature("decreaseBoldDebt(uint256)",amount));
    }
    function testOptionalReturnAndRollback() public {
        token.mint(address(active),1000);
        for(uint256 mode;mode<8;mode++) {
            token.setMode(mode);
            compare(address(active),abi.encodeWithSignature("receiveColl(uint256)",uint256(10)));
        }
        require(DefaultPool(a).getCollBalance()==30,"three accepted returns");
        token.setMode(3);
        compare(address(this),abi.encodeWithSignature("sendCollToActivePool(uint256)",uint256(10)));
        require(DefaultPool(a).getCollBalance()==30,"failed send rollback");
    }
    function testCodelessToken() public {
        vm.etch(address(token),hex"");
        compare(address(active),abi.encodeWithSignature("receiveColl(uint256)",uint256(0)));
    }
    function testCodelessActivePool() public {
        vm.etch(address(active),hex"");
        compare(address(this),abi.encodeWithSignature("sendCollToActivePool(uint256)",uint256(0)));
    }
}
