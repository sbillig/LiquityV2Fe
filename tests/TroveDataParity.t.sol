// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {TroveManager,IAddressesRegistry,LatestTroveData,LatestBatchData,TroveChange} from "../reference/bold/contracts/src/TroveManager.sol";
import {PoolVm} from "./DefaultPoolParity.t.sol";
interface TroveDataVm {
    function envOr(string calldata,string calldata) external returns(string memory);
    function warp(uint256) external;
    function store(address,bytes32,bytes32) external;
    function load(address,bytes32) external view returns(bytes32);
}
contract EmptyTroveRegistry {
    fallback() external {assembly{mstore(0,0) return(0,32)}}
}
contract TroveDataReference is TroveManager {
    constructor(IAddressesRegistry registry) TroveManager(registry) {}
    function updateBatch(uint id,address manager,TroveChange memory change,uint debt,uint coll,uint batchDebt,bool checkRatio) external {_updateBatchShares(id,manager,change,debt,coll,batchDebt,checkRatio);}
    function removeShares(uint id,uint coll,uint debt,TroveChange memory change,address manager,uint batchColl,uint batchDebt) external {_removeTroveSharesFromBatch(id,coll,debt,change,manager,batchColl,batchDebt);}
    function removeId(uint id,uint len) external {_removeTroveId(id,len);}
    function newStake(uint256 coll) external view returns(uint256){return _computeNewStake(coll);}
    function updateStake(uint256 id,uint256 coll) external returns(uint256){return _updateStakeAndTotalStakes(id,coll);}
    function updateRewards(uint256 id) external {_updateTroveRewardSnapshots(id);}
    function interestPeriod(uint256 last) external view returns(uint256){return _getInterestPeriod(last);}
}
contract TroveDataParityTest {
    PoolVm constant vm=PoolVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    TroveDataVm constant tv=TroveDataVm(address(vm));
    TroveDataReference a;TroveDataReference b;
    address constant BATCH=address(0xba7c);
    function setUp() public {
        tv.warp(10_000_000_000);
        bytes memory code=vm.parseBytes(vm.readFile(string.concat(tv.envOr("LIQUITY_TEST_ARTIFACTS","build"),"/TroveDataHarness.bin")));
        address created;assembly{created:=create(0,add(code,32),mload(code))}require(created.code.length>0);a=TroveDataReference(created);
        b=new TroveDataReference(IAddressesRegistry(address(new EmptyTroveRegistry())));
    }
    function write(uint slot,uint value) internal {tv.store(address(a),bytes32(slot),bytes32(value));tv.store(address(b),bytes32(slot),bytes32(value));}
    function mapped(uint key,uint root) internal pure returns(uint){return uint(keccak256(abi.encode(key,root)));}
    function seedTrove(uint id,uint debt,uint coll,uint stake,uint64 last,uint64 adjusted,uint rate,address manager,uint shares) internal {
        uint base=mapped(id,11);write(base,debt);write(base+1,coll);write(base+2,stake);write(base+3,1|(uint(123)<<8)|(uint(last)<<72)|(uint(adjusted)<<136));write(base+4,rate);write(base+5,uint160(manager));write(base+6,shares);
    }
    function seedBatch(uint debt,uint coll,uint64 last,uint64 adjusted,uint rate,uint fee,uint shares) internal {
        uint base=mapped(uint160(BATCH),12);write(base,debt);write(base+1,coll);write(base+2,5|(uint(last)<<64)|(uint(adjusted)<<128));write(base+3,rate);write(base+4,fee);write(base+5,shares);
    }
    function compare(bytes memory data) internal returns(bool){
        (bool x,bytes memory p)=address(a).call(data);(bool y,bytes memory q)=address(b).call(data);require(x==y,"success mismatch");require(keccak256(p)==keccak256(q),"return/revert mismatch");return x;
    }
    function checkTrove(uint id,uint price) internal {
        require(compare(abi.encodeWithSignature("Troves(uint256)",id)));require(compare(abi.encodeCall(a.getTroveStatus,(id))));require(compare(abi.encodeCall(a.getTroveAnnualInterestRate,(id))));
        require(compare(abi.encodeCall(a.getLatestTroveData,(id))));require(compare(abi.encodeCall(a.getCurrentICR,(id,price))));require(compare(abi.encodeWithSignature("rewardSnapshots(uint256)",id)));
    }
    function testIndividualInterestRedistributionAndShutdown() public {
        uint64 last=uint64(block.timestamp-365 days);seedTrove(1,2000e18,5e18,4e18,last,last+99,5e16,address(0),0);
        write(16,3e18);write(17,4e18);uint rewards=mapped(1,18);write(rewards,1e18);write(rewards+1,2e18);
        checkTrove(1,2000e18);LatestTroveData memory value=a.getLatestTroveData(1);
        require(value.accruedInterest==100e18&&value.redistBoldDebtGain==8e18&&value.redistCollGain==8e18&&value.entireDebt==2108e18&&value.entireColl==13e18);
        write(24,last+365 days/2);checkTrove(1,2000e18);require(a.getLatestTroveData(1).accruedInterest==50e18);
        write(24,last);checkTrove(1,2000e18);require(a.getLatestTroveData(1).accruedInterest==0);
        checkTrove(type(uint).max,1);
    }
    function testBatchUsesSeparateRoundingAndStakeRedistribution() public {
        uint64 last=uint64(block.timestamp-365 days);seedBatch(1001,777,last,last+100,123e15,17e15,7);
        seedTrove(7,999999,80,5e18,last,last+200,99999,BATCH,3);write(16,4e18);write(17,6e18);
        checkTrove(7,1e18);require(compare(abi.encodeCall(a.getLatestBatchData,(BATCH))));
        LatestTroveData memory t=a.getLatestTroveData(7);LatestBatchData memory batch=a.getLatestBatchData(BATCH);
        require(t.recordedDebt==1001*3/7&&t.accruedInterest==batch.accruedInterest*3/7&&t.accruedBatchManagementFee==batch.accruedManagementFee*3/7);
        require(t.redistBoldDebtGain==30e18&&t.redistCollGain==20e18&&t.lastInterestRateAdjTime==last+200&&t.annualInterestRate==123e15);
        write(mapped(uint160(BATCH),12)+5,0);checkTrove(7,1e18);t=a.getLatestTroveData(7);require(t.recordedDebt==0&&t.accruedInterest==0&&t.accruedBatchManagementFee==0&&t.entireDebt==30e18);
    }
    function testFuzzIndividualData(uint256 id,uint96 debt,uint96 coll,uint96 stake,uint64 rate,uint32 elapsed,uint64 reward,uint8 shutdown) public {
        uint64 last=uint64(block.timestamp-elapsed);seedTrove(id,debt,coll,stake,last,last+1,rate,address(0),0);write(16,reward);write(17,reward/3);
        if(shutdown%3==1)write(24,last+elapsed/2);else if(shutdown%3==2)write(24,last-1);
        checkTrove(id,1e18);
    }
    function testFuzzBatchData(uint96 debt,uint96 coll,uint96 shares,uint96 userShares,uint64 rate,uint64 fee,uint32 elapsed,uint64 reward) public {
        uint64 last=uint64(block.timestamp-elapsed);uint portion=shares==0?0:uint(userShares)%(uint(shares)+1);
        seedBatch(debt,coll,last,last+17,rate,fee,shares);seedTrove(9,0,coll,coll,last,last+9,0,BATCH,portion);write(16,reward);write(17,reward/7);
        require(compare(abi.encodeCall(a.getLatestBatchData,(BATCH))));checkTrove(9,1e18);
    }
    function testFuzzStakeUpdate(uint256 coll,uint256 stakesSnapshot,uint256 collSnapshot,uint256 oldStake,uint256 totalStakes) public {
        write(13,totalStakes);write(14,stakesSnapshot);write(15,collSnapshot);uint slot=mapped(1,11)+2;write(slot,oldStake);
        compare(abi.encodeCall(a.newStake,(coll)));compare(abi.encodeCall(a.updateStake,(1,coll)));
        require(tv.load(address(a),bytes32(slot))==tv.load(address(b),bytes32(slot))&&tv.load(address(a),bytes32(uint(13)))==tv.load(address(b),bytes32(uint(13))),"stake state");
        write(16,stakesSnapshot);write(17,collSnapshot);require(compare(abi.encodeCall(a.updateRewards,(1))));require(compare(abi.encodeWithSignature("rewardSnapshots(uint256)",1)));
    }
    function testFuzzInterestPeriod(uint256 last,uint256 shutdown) public {write(24,shutdown);compare(abi.encodeCall(a.interestPeriod,(last)));}

    function sameWords(uint base,uint count) internal view {
        for(uint i;i<count;i++)require(tv.load(address(a),bytes32(base+i))==tv.load(address(b),bytes32(base+i)),"storage mismatch");
    }
    function checkState() internal view {sameWords(mapped(1,11),7);sameWords(mapped(uint160(BATCH),12),6);}
    function prepareShares(uint shares,uint userShares) internal {
        seedBatch(123,456,77,88,99,111,shares);seedTrove(1,987,654,321,44,55,66,BATCH,userShares);
        // Preserve padding as well as adjacent packed fields.
        write(mapped(1,11)+3,uint(tv.load(address(a),bytes32(mapped(1,11)+3)))|(uint(0xabcdef)<<208));
        write(mapped(uint160(BATCH),12)+2,uint(tv.load(address(a),bytes32(mapped(uint160(BATCH),12)+2)))|(uint(0xaabbcc)<<192));
        tv.warp(uint(type(uint64).max)+123);
    }
    function testBatchShareBoundaries() public {
        prepareShares(7,3);TroveChange memory c;c.debtIncrease=1;
        require(compare(abi.encodeCall(a.updateBatch,(1,BATCH,c,1,777,7e9,true))));checkState();
        require(!compare(abi.encodeCall(a.updateBatch,(1,BATCH,c,1,777,7e9+1,true))));checkState();
        require(compare(abi.encodeCall(a.updateBatch,(1,BATCH,c,1,777,7e9+1,false))));checkState();
        prepareShares(type(uint).max,3);
        require(!compare(abi.encodeCall(a.updateBatch,(1,BATCH,c,1,777,1,false))));checkState();
        prepareShares(7,3);c.debtIncrease=0;c.debtDecrease=2;
        require(compare(abi.encodeCall(a.updateBatch,(1,BATCH,c,0,777,1000,true))));checkState();
        require(uint(tv.load(address(a),bytes32(mapped(1,11)+6)))==0);
        require(uint(tv.load(address(a),bytes32(mapped(uint160(BATCH),12)+5)))==4);
    }
    function testFuzzBatchShares(uint96 debt,uint96 shares,uint96 coll,uint64 amount,uint8 mode) public {
        prepareShares(shares,shares/2);TroveChange memory c;
        c.upfrontFee=amount/7;c.appliedRedistBoldDebtGain=amount/3;c.appliedRedistCollGain=amount/5;
        c.debtIncrease=amount;c.collIncrease=amount;
        if(mode%3==1){c.debtDecrease=2*uint(amount);c.collDecrease=2*uint(amount);}
        if(mode%3==2){c.debtDecrease=c.debtIncrease+c.upfrontFee+c.appliedRedistBoldDebtGain;c.collDecrease=c.collIncrease+c.appliedRedistCollGain;}
        compare(abi.encodeCall(a.updateBatch,(1,BATCH,c,mode%2,coll,debt,mode%2==0)));checkState();
    }
    function testFuzzBatchSharesOverflow(uint debt,uint shares,uint coll,TroveChange memory change,bool checkRatio) public {
        prepareShares(shares,shares/2);
        compare(abi.encodeCall(a.updateBatch,(1,BATCH,change,debt,coll,debt,checkRatio)));checkState();
    }
    function testRemoveBatchShares() public {
        prepareShares(100,30);TroveChange memory c;c.upfrontFee=10;c.appliedRedistBoldDebtGain=20;c.appliedRedistCollGain=40;
        require(compare(abi.encodeCall(a.removeShares,(1,100,200,c,BATCH,1000,2000))));checkState();
        uint base=mapped(uint160(BATCH),12);
        require(uint(tv.load(address(a),bytes32(base)))==1830&&uint(tv.load(address(a),bytes32(base+1)))==940&&uint(tv.load(address(a),bytes32(base+5)))==70);
        require(uint(tv.load(address(a),bytes32(mapped(1,11)+5)))==0);
    }
    function testFuzzRemoveShares(uint debt,uint coll,uint batchDebt,uint batchColl,uint shares,uint userShares,TroveChange memory c) public {
        prepareShares(shares,userShares);compare(abi.encodeCall(a.removeShares,(1,coll,debt,c,BATCH,batchColl,batchDebt)));checkState();
    }
    function testFuzzRemoveTroveId(uint8 length,uint8 index,uint8 suppliedLength) public {
        uint len=uint(length)%8;uint selected=uint(index)%10;uint passed=uint(suppliedLength)%10;
        write(19,len);uint base=uint(keccak256(abi.encode(uint(19))));
        for(uint i;i<len;i++){write(base+i,i+1);seedTrove(i+1,11,22,33,44,55,66,address(0),0);write(mapped(i+1,11)+3,1|(i<<8)|(uint(44)<<72)|(uint(55)<<136));}
        compare(abi.encodeCall(a.removeId,(selected+1,passed)));sameWords(19,1);sameWords(base,10);
        for(uint i;i<11;i++)sameWords(mapped(i,11),7);
    }
}
