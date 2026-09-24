// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {ActivePool} from "../reference/bold/contracts/src/ActivePool.sol";
import {IAddressesRegistry} from "../reference/bold/contracts/src/Interfaces/IAddressesRegistry.sol";
import {TroveChange} from "../reference/bold/contracts/src/Types/TroveChange.sol";
import {PoolVm} from "./DefaultPoolParity.t.sol";
interface TimeVm {function warp(uint256) external;}
contract ActiveCollateralToken {
    mapping(address=>uint256) public balanceOf;
    mapping(address=>mapping(address=>uint256)) public allowance;
    bool public fail;
    function setFail(bool f) external {fail=f;}
    function mint(address to,uint256 n) external {balanceOf[to]+=n;}
    function approve(address to,uint256 n) external returns(bool) {allowance[msg.sender][to]=n;return true;}
    function transfer(address to,uint256 n) external returns(bool) {
        require(!fail,"collateral failure");balanceOf[msg.sender]-=n;balanceOf[to]+=n;return true;
    }
    function transferFrom(address from,address to,uint256 n) external returns(bool) {
        require(!fail,"collateral failure");allowance[from][msg.sender]-=n;balanceOf[from]-=n;balanceOf[to]+=n;return true;
    }
}
contract MintRecorder {
    mapping(address=>mapping(address=>uint256)) public minted;
    mapping(address=>uint256) public count;
    bool public fail;
    function setFail(bool f) external {fail=f;}
    function mint(address to,uint256 n) external {require(!fail,"mint failure");minted[msg.sender][to]+=n;count[msg.sender]++;}
}
contract RewardsRecorder {
    mapping(address=>uint256) public rewards;
    bool public fail;
    function setFail(bool f) external {fail=f;}
    function triggerBoldRewards(uint256 n) external {require(!fail,"rewards failure");rewards[msg.sender]+=n;}
}
contract DefaultReceiver {
    ActiveCollateralToken token;
    mapping(address=>uint256) public received;
    constructor(ActiveCollateralToken t){token=t;}
    function receiveColl(uint256 n) external {received[msg.sender]+=n;token.transferFrom(msg.sender,address(this),n);}
}
contract ActiveRegistryMock {
    address public collToken;address public borrowerOperations;address public troveManager;
    address public stabilityPool;address public defaultPool;address public interestRouter;address public boldToken;
    constructor(address t,address bo,address tm,address sp,address dp,address ir,address bold) {
        collToken=t;borrowerOperations=bo;troveManager=tm;stabilityPool=sp;defaultPool=dp;interestRouter=ir;boldToken=bold;
    }
}
contract ActivePoolParityTest {
    PoolVm constant vm=PoolVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    TimeVm constant clock=TimeVm(address(vm));
    address constant BO=address(0xb0);address constant ROUTER=address(0x100);address constant BATCH=address(0xba);
    ActivePool a;ActivePool b;
    ActiveCollateralToken token;MintRecorder bold;RewardsRecorder sp;DefaultReceiver dp;
    function setUp() public {
        clock.warp(1000);
        token=new ActiveCollateralToken();bold=new MintRecorder();sp=new RewardsRecorder();dp=new DefaultReceiver(token);
        ActiveRegistryMock reg=new ActiveRegistryMock(address(token),BO,address(this),address(sp),address(dp),ROUTER,address(bold));
        bytes memory code=bytes.concat(vm.parseBytes(vm.readFile("build/ActivePool.bin")),abi.encode(reg));
        vm.recordLogs();address deployed;assembly {deployed:=create(0,add(code,32),mload(code))}
        require(deployed.code.length>0,"Fe deploy");a=ActivePool(deployed);
        PoolVm.Log[] memory logs=vm.getRecordedLogs();vm.recordLogs();
        b=new ActivePool(IAddressesRegistry(address(reg)));logsEqual(logs,vm.getRecordedLogs());
        vm.prank(BO);token.approve(address(a),type(uint256).max);
        vm.prank(BO);token.approve(address(b),type(uint256).max);
    }
    function logsEqual(PoolVm.Log[] memory x,PoolVm.Log[] memory y) internal pure {
        require(x.length==y.length,"logs");
        for(uint i;i<x.length;i++) {
            require(keccak256(abi.encode(x[i].topics))==keccak256(abi.encode(y[i].topics)),"topics");
            require(keccak256(x[i].data)==keccak256(y[i].data),"data");
        }
    }
    function compare(address caller,bytes memory data) internal returns(bool) {
        vm.recordLogs();vm.prank(caller);(bool x,bytes memory rx)=address(a).call(data);
        PoolVm.Log[] memory logs=vm.getRecordedLogs();
        vm.recordLogs();vm.prank(caller);(bool y,bytes memory ry)=address(b).call(data);
        logsEqual(logs,vm.getRecordedLogs());require(x==y,"success");require(keccak256(rx)==keccak256(ry),"result");
        stateEqual();return x;
    }
    function sameView(bytes memory data) internal view {
        (bool x,bytes memory rx)=address(a).staticcall(data);(bool y,bytes memory ry)=address(b).staticcall(data);
        require(x==y,"getter success");require(keccak256(rx)==keccak256(ry),"getter result");
    }
    function stateEqual() internal view {
        require(a.getCollBalance()==b.getCollBalance(),"coll");
        require(a.aggRecordedDebt()==b.aggRecordedDebt(),"debt");
        require(a.aggWeightedDebtSum()==b.aggWeightedDebtSum(),"weight");
        require(a.lastAggUpdateTime()==b.lastAggUpdateTime(),"updated");
        require(a.shutdownTime()==b.shutdownTime(),"shutdown");
        require(a.aggBatchManagementFees()==b.aggBatchManagementFees(),"fees");
        require(a.aggWeightedBatchManagementFeeSum()==b.aggWeightedBatchManagementFeeSum(),"fee weight");
        require(a.lastAggBatchManagementFeesUpdateTime()==b.lastAggBatchManagementFeesUpdateTime(),"fee updated");
        sameView(abi.encodeCall(a.calcPendingAggInterest,()));
        sameView(abi.encodeCall(a.calcPendingSPYield,()));
        sameView(abi.encodeCall(a.calcPendingAggBatchManagementFee,()));
        sameView(abi.encodeCall(a.getBoldDebt,()));
        require(bold.minted(address(a),ROUTER)==bold.minted(address(b),ROUTER),"router yield");
        require(bold.minted(address(a),address(sp))==bold.minted(address(b),address(sp)),"SP yield");
        require(bold.minted(address(a),BATCH)==bold.minted(address(b),BATCH),"batch yield");
        require(bold.count(address(a))==bold.count(address(b)),"mint calls");
        require(sp.rewards(address(a))==sp.rewards(address(b)),"rewards");
        require(token.balanceOf(address(a))==token.balanceOf(address(b)),"coll token");
        require(dp.received(address(a))==dp.received(address(b)),"default received");
    }
    function open(uint256 debt,uint256 rate,uint256 feeRate,uint256 upfront) internal {
        TroveChange memory c;c.debtIncrease=debt;c.newWeightedRecordedDebt=debt*rate;c.upfrontFee=upfront;
        c.newWeightedRecordedBatchManagementFee=debt*feeRate;
        require(compare(BO,abi.encodeCall(a.mintAggInterestAndAccountForTroveChange,(c,BATCH))),"open failed");
    }
    function testGetters() public {
        sameView(abi.encodeWithSignature("NAME()"));
        sameView(abi.encodeWithSignature("collToken()"));
        sameView(abi.encodeWithSignature("borrowerOperationsAddress()"));
        sameView(abi.encodeWithSignature("troveManagerAddress()"));
        sameView(abi.encodeWithSignature("defaultPoolAddress()"));
        sameView(abi.encodeWithSignature("boldToken()"));
        sameView(abi.encodeWithSignature("interestRouter()"));
        sameView(abi.encodeWithSignature("stabilityPool()"));
        sameView(abi.encodeWithSignature("hasBeenShutDown()"));stateEqual();
        require(token.allowance(address(a),address(dp))==type(uint256).max);
    }
    function testFuzzInterestAndBatch(uint96 amount,uint64 rateSeed,uint64 feeSeed,uint32 elapsed) public {
        uint256 debt=2000e18+uint256(amount);uint256 rate=uint256(rateSeed)%25e17;
        uint256 fee=uint256(feeSeed)%1e17;uint256 duration=uint256(elapsed)%315360000;
        open(debt,rate,fee,7);
        clock.warp(1000+duration);stateEqual();
        uint256 pending=b.calcPendingAggInterest();
        uint256 feeFloor=debt*fee*duration/365 days/1e18;
        TroveChange memory c;c.batchAccruedManagementFee=feeFloor;
        require(compare(address(this),abi.encodeCall(a.mintBatchManagementFeeAndAccountForChange,(c,BATCH))),"batch mint");
        require(compare(address(sp),abi.encodeCall(a.mintAggInterest,())),"interest mint");
        require(a.aggRecordedDebt()==debt+7+feeFloor+pending,"recorded amount");
        require(bold.minted(address(a),BATCH)==feeFloor,"manager fee");
        uint256 spAmount=uint256(7)*75/100+pending*75/100;
        require(sp.rewards(address(a))==spAmount,"yield split");
        sameView(abi.encodeCall(a.getNewApproxAvgInterestRateFromTroveChange,(c)));
        c.debtDecrease=a.aggRecordedDebt();c.batchAccruedManagementFee=0;
        c.oldWeightedRecordedDebt=debt*rate;c.oldWeightedRecordedBatchManagementFee=debt*fee;
        require(compare(BO,abi.encodeCall(a.mintAggInterestAndAccountForTroveChange,(c,BATCH))),"close");
        require(a.aggRecordedDebt()==0&&a.aggWeightedDebtSum()==0&&a.aggWeightedBatchManagementFeeSum()==0);
    }
    function testShutdownFreezesInterestAndBatchPeriod() public {
        open(2000e18,5e16,1e16,0);clock.warp(1000+30 days);
        uint256 pendingBatch=b.calcPendingAggBatchManagementFee();
        require(compare(address(this),abi.encodeCall(a.setShutdownFlag,())));
        require(a.calcPendingAggInterest()==0);clock.warp(1000+60 days);
        require(a.calcPendingAggBatchManagementFee()==pendingBatch);
        TroveChange memory c;c.batchAccruedManagementFee=pendingBatch;c.upfrontFee=1;
        require(compare(BO,abi.encodeCall(a.mintAggInterestAndAccountForTroveChange,(c,BATCH))));
        require(a.calcPendingAggBatchManagementFee()==0);
        require(a.aggRecordedDebt()==2000e18+pendingBatch+1);
        c.upfrontFee=0;sameView(abi.encodeCall(a.getNewApproxAvgInterestRateFromTroveChange,(c)));
        require(compare(address(this),abi.encodeCall(a.setShutdownFlag,())));
    }
    function testFuzzRawChange(TroveChange memory c) public {
        open(2000e18,5e16,1e16,0);clock.warp(1000+365 days);
        sameView(abi.encodeCall(a.getNewApproxAvgInterestRateFromTroveChange,(c)));
        compare(BO,abi.encodeCall(a.mintAggInterestAndAccountForTroveChange,(c,BATCH)));
        compare(address(this),abi.encodeCall(a.mintBatchManagementFeeAndAccountForChange,(c,BATCH)));
    }
    function testFuzzCollateral(uint128 amount,uint128 outgoing) public {
        token.mint(BO,uint256(amount)*2);
        require(compare(BO,abi.encodeCall(a.receiveColl,(amount))));
        compare(address(this),abi.encodeCall(a.sendCollToDefaultPool,(outgoing)));
        compare(address(sp),abi.encodeCall(a.sendColl,(ROUTER,outgoing)));
        compare(BO,abi.encodeCall(a.accountForReceivedColl,(amount)));
    }
    function testFuzzUnauthorized(address caller,uint256 amount) public {
        if(caller==BO||caller==address(this)||caller==address(sp)||caller==address(dp))return;
        TroveChange memory c;
        compare(caller,abi.encodeCall(a.receiveColl,(amount)));
        compare(caller,abi.encodeCall(a.accountForReceivedColl,(amount)));
        compare(caller,abi.encodeCall(a.sendColl,(ROUTER,amount)));
        compare(caller,abi.encodeCall(a.sendCollToDefaultPool,(amount)));
        compare(caller,abi.encodeCall(a.mintAggInterest,()));
        compare(caller,abi.encodeCall(a.mintAggInterestAndAccountForTroveChange,(c,BATCH)));
        compare(caller,abi.encodeCall(a.mintBatchManagementFeeAndAccountForChange,(c,BATCH)));
        compare(caller,abi.encodeCall(a.setShutdownFlag,()));
    }
    function testExternalFailureRollback() public {
        open(2000e18,5e16,1e16,0);clock.warp(1000+365 days);
        bold.setFail(true);compare(BO,abi.encodeCall(a.mintAggInterest,()));
        require(a.lastAggUpdateTime()==1000);bold.setFail(false);
        sp.setFail(true);compare(BO,abi.encodeCall(a.mintAggInterest,()));
        require(a.aggRecordedDebt()==2000e18&&bold.count(address(a))==0);
        sp.setFail(false);require(compare(BO,abi.encodeCall(a.mintAggInterest,())));
        token.mint(BO,20);token.setFail(true);compare(BO,abi.encodeCall(a.receiveColl,(uint256(10))));
        require(a.getCollBalance()==0);token.setFail(false);
        require(compare(BO,abi.encodeCall(a.receiveColl,(uint256(10)))));
        token.setFail(true);compare(address(this),abi.encodeCall(a.sendCollToDefaultPool,(uint256(10))));
        require(a.getCollBalance()==10);
    }
    function testPrivilegedRoleBoundaries() public {
        address[4] memory roles=[BO,address(this),address(sp),address(dp)];
        TroveChange memory c;
        for(uint i;i<4;i++) {
            compare(roles[i],abi.encodeCall(a.receiveColl,(uint256(0))));
            compare(roles[i],abi.encodeCall(a.accountForReceivedColl,(uint256(0))));
            compare(roles[i],abi.encodeCall(a.sendColl,(ROUTER,uint256(0))));
            compare(roles[i],abi.encodeCall(a.sendCollToDefaultPool,(uint256(0))));
            compare(roles[i],abi.encodeCall(a.mintAggInterest,()));
            compare(roles[i],abi.encodeCall(a.mintAggInterestAndAccountForTroveChange,(c,address(0))));
            compare(roles[i],abi.encodeCall(a.mintBatchManagementFeeAndAccountForChange,(c,address(0))));
        }
    }
    function testTinyInterestRoundsUpAndSkipsZeroSPYield() public {
        open(1,1,0,0);clock.warp(1001);
        require(a.calcPendingAggInterest()==1);
        require(compare(BO,abi.encodeCall(a.mintAggInterest,())));
        require(a.aggRecordedDebt()==2);
        require(bold.minted(address(a),ROUTER)==1);
        require(bold.minted(address(a),address(sp))==0);
        require(bold.count(address(a))==1);
        require(compare(BO,abi.encodeCall(a.mintAggInterest,())));
        require(bold.count(address(a))==1);
    }

}
