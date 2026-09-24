// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {TroveManager,IAddressesRegistry,TroveChange} from "../reference/bold/contracts/src/TroveManager.sol";
import {ITroveManager} from "../reference/bold/contracts/src/Interfaces/ITroveManager.sol";
import {PoolVm} from "./DefaultPoolParity.t.sol";
import {TroveDataVm,EmptyTroveRegistry} from "./TroveDataParity.t.sol";
contract TroveHookDependency {
    event Called(bytes data);
    bool public fail;
    function setFail(bool value) external {fail=value;}
    fallback() external {require(!fail,"dependency failure");emit Called(msg.data);}
}
contract TroveHooksParityTest {
    PoolVm constant vm=PoolVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    TroveDataVm constant tv=TroveDataVm(address(vm));
    TroveManager a;TroveManager b;TroveHookDependency dep;
    address constant BATCH=address(0xba7c);
    function setUp() public {
        tv.warp(10_000_000_000);dep=new TroveHookDependency();
        bytes memory code=bytes.concat(vm.parseBytes(vm.readFile(string.concat(tv.envOr("LIQUITY_TEST_ARTIFACTS","build"),"/TroveHookHarness.bin"))),abi.encode(address(this),address(dep),address(dep),address(dep)));
        address created;assembly{created:=create(0,add(code,32),mload(code))}require(created.code.length>0);a=TroveManager(created);
        b=new TroveManager(IAddressesRegistry(address(new EmptyTroveRegistry())));
        write(1,uint160(address(dep)));write(3,uint160(address(dep)));write(4,uint160(address(this)));write(9,uint160(address(dep)));
    }
    function write(uint slot,uint value) internal {tv.store(address(a),bytes32(slot),bytes32(value));tv.store(address(b),bytes32(slot),bytes32(value));}
    function mapped(uint key,uint root) internal pure returns(uint){return uint(keccak256(abi.encode(key,root)));}
    function same(uint slot,uint count) internal view {
        for(uint i;i<count;i++)require(tv.load(address(a),bytes32(slot+i))==tv.load(address(b),bytes32(slot+i)),"storage mismatch");
    }
    function checkState() internal view {
        same(11,14);for(uint i;i<5;i++){same(mapped(i,11),7);same(mapped(i,18),2);}
        same(mapped(uint160(BATCH),12),6);same(uint(keccak256(abi.encode(uint(19)))),6);same(uint(keccak256(abi.encode(uint(20)))),6);
    }
    function compare(bytes memory data) internal returns(bool){
        vm.recordLogs();(bool x,bytes memory p)=address(a).call(data);PoolVm.Log[] memory lx=vm.getRecordedLogs();
        vm.recordLogs();(bool y,bytes memory q)=address(b).call(data);PoolVm.Log[] memory ly=vm.getRecordedLogs();
        require(x==y,"success mismatch");require(keccak256(p)==keccak256(q),"return/revert mismatch");
        require(lx.length==ly.length,"event count");
        for(uint i;i<lx.length;i++){
            require(keccak256(abi.encode(lx[i].topics,lx[i].data))==keccak256(abi.encode(ly[i].topics,ly[i].data)),"event mismatch");
            require((lx[i].emitter==address(a)&&ly[i].emitter==address(b))||lx[i].emitter==ly[i].emitter,"emitter mismatch");
        }
        checkState();return x;
    }
    function open(uint id,bool batch) internal {
        TroveChange memory c;c.collIncrease=10e18;c.debtIncrease=2000e18;c.upfrontFee=10e18;
        if(batch)require(compare(abi.encodeCall(a.onOpenTroveAndJoinBatch,(address(this),id,c,BATCH,0,0))));
        else require(compare(abi.encodeCall(a.onOpenTrove,(address(this),id,c,5e16))));
    }
    function testIndividualHooksLifecycle() public {
        write(16,123);write(17,456);open(1,false);open(2,false);
        TroveChange memory c;c.appliedRedistBoldDebtGain=1e18;c.appliedRedistCollGain=2e18;c.upfrontFee=3e18;
        require(compare(abi.encodeCall(a.onAdjustTroveInterestRate,(1,12e18,2014e18,7e16,c))));
        c.debtIncrease=100e18;c.collIncrease=4e18;
        require(compare(abi.encodeCall(a.onAdjustTrove,(1,16e18,2114e18,c))));
        require(compare(abi.encodeCall(a.onApplyTroveInterest,(1,16e18,2200e18,address(0),0,0,c))));
        c.debtDecrease=2200e18;c.collDecrease=16e18;
        require(compare(abi.encodeCall(a.onCloseTrove,(1,c,address(0),0,0))));
        require(!compare(abi.encodeCall(a.onCloseTrove,(2,c,address(0),0,0))));
        write(24,block.timestamp);require(compare(abi.encodeCall(a.onCloseTrove,(2,c,address(0),0,0))));
    }
    function testBatchHooksLifecycle() public {
        require(compare(abi.encodeCall(a.onRegisterBatchManager,(BATCH,5e16,1e16))));open(1,true);open(2,false);
        require(compare(abi.encodeCall(a.onLowerBatchManagerAnnualFee,(BATCH,10e18,2050e18,5e15))));
        require(compare(abi.encodeCall(a.onSetBatchManagerAnnualInterestRate,(BATCH,10e18,2060e18,6e16,10e18))));
        TroveChange memory c;c.collIncrease=1e18;c.debtIncrease=100e18;c.upfrontFee=3e18;c.appliedRedistBoldDebtGain=1e18;c.appliedRedistCollGain=2e18;
        require(compare(abi.encodeCall(a.onAdjustTroveInsideBatch,(1,13e18,2164e18,c,BATCH,10e18,2060e18))));
        TroveChange memory z;require(compare(abi.encodeCall(a.onApplyTroveInterest,(1,13e18,2200e18,BATCH,13e18,2200e18,z))));
        require(compare(abi.encodeCall(a.onRemoveFromBatch,(1,13e18,2200e18,z,BATCH,13e18,2200e18,8e16))));
    }
    function testDependencyRollbackAndAuthorization() public {
        dep.setFail(true);TroveChange memory c;c.debtIncrease=2000e18;c.collIncrease=10e18;
        require(!compare(abi.encodeCall(a.onOpenTrove,(address(this),1,c,5e16))));
        dep.setFail(false);write(4,123);require(!compare(abi.encodeCall(a.onOpenTrove,(address(this),1,c,5e16))));
        require(!compare(abi.encodeCall(a.setTroveStatusToActive,(1))));
        write(4,uint160(address(this)));write(3,123);require(!compare(abi.encodeCall(a.onOpenTrove,(address(this),1,c,5e16))));
    }
    function testFuzzOpenAdjust(uint96 debt,uint96 coll,uint64 fee,uint64 rate,uint64 nextColl,uint64 nextDebt) public {
        TroveChange memory c;c.debtIncrease=debt;c.collIncrease=coll;c.upfrontFee=fee;
        require(compare(abi.encodeCall(a.onOpenTrove,(address(this),1,c,rate))));
        c.debtDecrease=nextDebt;c.collDecrease=nextColl;
        require(compare(abi.encodeCall(a.onAdjustTrove,(1,nextColl,nextDebt,c))));
    }
    function testClosePreservesPackedPadding() public {
        open(1,false);open(2,false);uint base=mapped(1,11);
        write(base+3,uint(tv.load(address(a),bytes32(base+3)))|(uint(0xaabbcc)<<208));
        write(base+5,uint(0xaabbcc)<<160);
        TroveChange memory c;c.debtDecrease=2010e18;c.collDecrease=10e18;
        require(compare(abi.encodeCall(a.onCloseTrove,(1,c,address(0),0,0))));
    }
    function testActivateZombieAndTimestampTruncation() public {
        tv.warp(uint(type(uint64).max)+99);open(1,false);write(21,1);
        require(compare(abi.encodeCall(a.setTroveStatusToActive,(1))));
        require(compare(abi.encodeCall(a.onRegisterBatchManager,(BATCH,5e16,1e16))));
    }

    function testJoinBatchAndCloseBatchTrove() public {
        open(1,false);open(2,false);
        require(compare(abi.encodeCall(a.onRegisterBatchManager,(BATCH,5e16,1e16))));
        TroveChange memory c;c.appliedRedistBoldDebtGain=3e18;c.appliedRedistCollGain=1e18;c.upfrontFee=5e18;
        ITroveManager.OnSetInterestBatchManagerParams memory p=ITroveManager.OnSetInterestBatchManagerParams(1,11e18,2020e18,c,BATCH,0,0);
        require(compare(abi.encodeCall(a.onSetInterestBatchManager,(p))));
        TroveChange memory closeChange;closeChange.collDecrease=11e18;closeChange.debtDecrease=2020e18;
        require(compare(abi.encodeCall(a.onCloseTrove,(1,closeChange,BATCH,11e18,2020e18))));
    }
    function testFuzzHookErrors(TroveChange memory c,uint256 coll,uint256 debt,uint256 rate,uint8 op) public {
        open(1,false);open(2,false);
        if(op%5==0)compare(abi.encodeCall(a.onAdjustTrove,(1,coll,debt,c)));
        else if(op%5==1)compare(abi.encodeCall(a.onAdjustTroveInterestRate,(1,coll,debt,rate,c)));
        else if(op%5==2)compare(abi.encodeCall(a.onApplyTroveInterest,(1,coll,debt,address(0),0,0,c)));
        else if(op%5==3)compare(abi.encodeCall(a.onAdjustTroveInsideBatch,(1,coll,debt,c,BATCH,coll,debt)));
        else compare(abi.encodeCall(a.onRemoveFromBatch,(1,coll,debt,c,BATCH,coll,debt,rate)));
    }
}
