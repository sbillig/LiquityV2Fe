// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {CollSurplusPool} from "../reference/bold/contracts/src/CollSurplusPool.sol";
import {IAddressesRegistry} from "../reference/bold/contracts/src/Interfaces/IAddressesRegistry.sol";
import {PoolVm} from "./DefaultPoolParity.t.sol";
contract SurplusToken {
    uint256 public mode;
    mapping(address=>uint256) public balanceOf;
    function setMode(uint256 m) external {mode=m;}
    function mint(address to,uint256 amount) external {balanceOf[to]+=amount;}
    function transfer(address to,uint256 amount) external returns(bool) {
        balanceOf[msg.sender]-=amount;balanceOf[to]+=amount;
        if(mode==1) return false;
        if(mode==2) {assembly {return(0,0)}}
        if(mode==3) revert("token reverted");
        if(mode==4) {assembly {revert(0,0)}}
        if(mode==5) {assembly {mstore(0,2) return(0,32)}}
        return true;
    }
}
contract SurplusRegistryMock {
    address public collToken;
    address public borrowerOperations;
    address public troveManager;
    constructor(address t,address b,address m){collToken=t;borrowerOperations=b;troveManager=m;}
}
contract SurplusPoolParityTest {
    PoolVm constant vm=PoolVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address constant BO=address(0xb0);
    SurplusToken token;
    address a; address b;
    function setUp() public {
        token=new SurplusToken();
        SurplusRegistryMock reg=new SurplusRegistryMock(address(token),BO,address(this));
        bytes memory code=bytes.concat(vm.parseBytes(vm.readFile("build/CollSurplusPool.bin")),abi.encode(reg));
        vm.recordLogs();address deployed;assembly {deployed:=create(0,add(code,32),mload(code))}
        a=deployed;require(a.code.length>0);
        PoolVm.Log[] memory logs=vm.getRecordedLogs();
        vm.recordLogs();b=address(new CollSurplusPool(IAddressesRegistry(address(reg))));
        logsEqual(logs,vm.getRecordedLogs());
    }
    function logsEqual(PoolVm.Log[] memory x,PoolVm.Log[] memory y) internal pure {
        require(x.length==y.length,"log count");
        for(uint i;i<x.length;i++) {
            require(keccak256(abi.encode(x[i].topics))==keccak256(abi.encode(y[i].topics)),"topics");
            require(keccak256(x[i].data)==keccak256(y[i].data),"data");
        }
    }
    function compare(address caller,bytes memory data,address account) internal {
        vm.recordLogs();vm.prank(caller);(bool x,bytes memory rx)=a.call(data);
        PoolVm.Log[] memory logs=vm.getRecordedLogs();
        vm.recordLogs();vm.prank(caller);(bool y,bytes memory ry)=b.call(data);
        logsEqual(logs,vm.getRecordedLogs());
        require(x==y,"success");require(keccak256(rx)==keccak256(ry),"result");
        require(CollSurplusPool(a).getCollBalance()==CollSurplusPool(b).getCollBalance(),"total");
        require(CollSurplusPool(a).getCollateral(account)==CollSurplusPool(b).getCollateral(account),"account");
        if(address(token).code.length>0) require(token.balanceOf(a)==token.balanceOf(b),"token balance");
    }
    function testGettersAndEmptyClaim() public {
        compare(BO,abi.encodeWithSignature("NAME()"),BO);
        compare(BO,abi.encodeWithSignature("collToken()"),BO);
        compare(BO,abi.encodeWithSignature("borrowerOperationsAddress()"),BO);
        compare(BO,abi.encodeWithSignature("troveManagerAddress()"),BO);
        compare(BO,abi.encodeWithSignature("claimColl(address)",BO),BO);
    }
    function testFuzzAccountAndClaim(address account,uint128 amount,uint128 more) public {
        if(account==a||account==b) return;
        uint256 total=uint256(amount)+more;
        token.mint(a,total);token.mint(b,total);
        compare(address(this),abi.encodeWithSignature("accountSurplus(address,uint256)",account,amount),account);
        compare(address(this),abi.encodeWithSignature("accountSurplus(address,uint256)",account,more),account);
        require(CollSurplusPool(a).getCollateral(account)==total);
        compare(BO,abi.encodeWithSignature("claimColl(address)",account),account);
        require(CollSurplusPool(a).getCollateral(account)==0);
        require(token.balanceOf(account)==total*2,"claimed token amount");
        compare(BO,abi.encodeWithSignature("claimColl(address)",account),account);
    }
    function testFuzzOverflowAndSeparation(uint256 first,uint256 second) public {
        compare(address(this),abi.encodeWithSignature("accountSurplus(address,uint256)",address(1),first),address(1));
        compare(address(this),abi.encodeWithSignature("accountSurplus(address,uint256)",address(2),second),address(2));
        compare(address(this),abi.encodeWithSignature("accountSurplus(address,uint256)",address(1),second),address(1));
    }
    function testFuzzUnauthorized(address caller,uint256 amount) public {
        if(caller==address(this)||caller==BO)return;
        compare(caller,abi.encodeWithSignature("accountSurplus(address,uint256)",caller,amount),caller);
        compare(caller,abi.encodeWithSignature("claimColl(address)",caller),caller);
    }
    function testClaimRollback() public {
        token.mint(a,10);token.mint(b,10);
        compare(address(this),abi.encodeWithSignature("accountSurplus(address,uint256)",BO,uint256(10)),BO);
        for(uint256 mode=1;mode<=5;mode++) {
            if(mode==2) continue;
            token.setMode(mode);compare(BO,abi.encodeWithSignature("claimColl(address)",BO),BO);
            require(CollSurplusPool(a).getCollateral(BO)==10,"claim rollback");
        }
        token.setMode(2);compare(BO,abi.encodeWithSignature("claimColl(address)",BO),BO);
        require(CollSurplusPool(a).getCollBalance()==0);
    }
    function testCodelessToken() public {
        compare(address(this),abi.encodeWithSignature("accountSurplus(address,uint256)",BO,uint256(1)),BO);
        vm.etch(address(token),hex"");compare(BO,abi.encodeWithSignature("claimColl(address)",BO),BO);
        require(CollSurplusPool(a).getCollateral(BO)==1);
    }
}
