// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {BorrowerOperations,IAddressesRegistry,IBorrowerOperations,LatestTroveData,LatestBatchData,TroveChange} from "../reference/bold/contracts/src/BorrowerOperations.sol";
import {PoolVm} from "./DefaultPoolParity.t.sol";
import {TroveDataVm} from "./TroveDataParity.t.sol";
contract BorrowerDependency {
    event Called(bytes data);
    uint public status;
    uint public price=2000e18;
    bool public failure;
    bool public fail;
    uint public average=5e16;
    uint public branchColl=1000e18;
    uint public branchDebt=100000e18;
    uint public balance=type(uint).max;
    address public owner;
    LatestTroveData internal trove;
    LatestBatchData internal batch;
    constructor(address o){owner=o;trove.entireDebt=3000e18;trove.entireColl=10e18;trove.annualInterestRate=5e16;trove.weightedRecordedDebt=3000e18*5e16;batch.entireDebtWithoutRedistribution=10000e18;batch.entireCollWithoutRedistribution=100e18;batch.annualInterestRate=6e16;batch.annualManagementFee=1e16;batch.weightedRecordedDebt=10000e18*6e16;batch.weightedRecordedBatchManagementFee=10000e18*1e16;batch.totalDebtShares=10000e18;}
    function configure(uint s,uint p,bool f) external {status=s;price=p;failure=f;}
    function setFail(bool f) external {fail=f;}
    function setBalance(uint v) external {balance=v;}
    function setTroves(LatestTroveData calldata t,LatestBatchData calldata b) external {trove=t;batch=b;}
    function getLatestTroveData(uint) external view returns(LatestTroveData memory){return trove;}
    function getLatestBatchData(address) external view returns(LatestBatchData memory){return batch;}
    function getTroveStatus(uint) external view returns(uint8){return uint8(status);}
    function getTroveAnnualInterestRate(uint) external view returns(uint){return trove.annualInterestRate;}
    function getNewApproxAvgInterestRateFromTroveChange(TroveChange calldata) external view returns(uint){return average;}
    function getCollBalance() external view returns(uint){return branchColl;}
    function getBoldDebt() external view returns(uint){return branchDebt;}
    function balanceOf(address) external view returns(uint){return balance;}
    function ownerOf(uint) external view returns(address){return owner;}
    function isEmptyBatch(address) external pure returns(bool){return false;}
    function fetchPrice() external returns(uint,bool){emit Called(msg.data);return(price,failure);}
    function approve(address,uint) external returns(bool){emit Called(msg.data);return true;}
    function transferFrom(address,address,uint) external returns(bool){require(!fail,"dependency failure");emit Called(msg.data);return true;}
    fallback() external {require(!fail,"dependency failure");emit Called(msg.data);}
}
contract BorrowerRegistry {
    event WETHRead();
    address internal dep;
    constructor(address d){dep=d;}
    function WETH() external returns(address){emit WETHRead();return dep;}
    function CCR() external pure returns(uint){return 15e17;}
    function SCR() external pure returns(uint){return 11e17;}
    function MCR() external pure returns(uint){return 11e17;}
    function BCR() external pure returns(uint){return 1e17;}
    fallback() external {address d=dep;assembly{mstore(0,d) return(0,32)}}
}
contract BorrowerOperationsParityTest {
    PoolVm constant vm=PoolVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    TroveDataVm constant tv=TroveDataVm(address(vm));
    BorrowerOperations a; BorrowerOperations b; BorrowerDependency dep;
    address constant BATCH=address(0xba7c);
    uint constant ID=7;
    function setUp() public {
        tv.warp(10_000_000_000);
        dep=new BorrowerDependency(address(this));
        IAddressesRegistry registry=IAddressesRegistry(address(new BorrowerRegistry(address(dep))));
        address opening=deployModule("BorrowerOpening",registry);
        address adjustments=deployModule("BorrowerAdjustments",registry);
        address batches=deployModule("BorrowerBatches",registry);
        bytes memory code=bytes.concat(vm.parseBytes(vm.readFile(string.concat(tv.envOr("LIQUITY_BORROWER_ARTIFACTS","build"),"/BorrowerOperations.bin"))),abi.encode(registry,opening,adjustments,batches));
        vm.recordLogs();address created;assembly{created:=create(0,add(code,32),mload(code))}require(created.code.length>0&&created.code.length<=24576,"Fe deploy");a=BorrowerOperations(created);
        PoolVm.Log[] memory logs=vm.getRecordedLogs();
        vm.recordLogs();b=new BorrowerOperations(registry);logsEqual(logs,vm.getRecordedLogs());
        checkState();
    }
    function deployModule(string memory name,IAddressesRegistry registry) internal returns(address created){
        bytes memory init=bytes.concat(vm.parseBytes(vm.readFile(string.concat(tv.envOr("LIQUITY_BORROWER_ARTIFACTS","build"),"/",name,".bin"))),abi.encode(registry));
        require(init.length<=49152,"module initcode size");
        assembly{created:=create(0,add(init,32),mload(init))}
        require(created.code.length>0&&created.code.length<=24576,"module runtime size");
    }
    function logsEqual(PoolVm.Log[] memory x,PoolVm.Log[] memory y) internal view {
        require(x.length==y.length,"event count");
        for(uint i;i<x.length;i++){
            require(keccak256(abi.encode(x[i].topics,x[i].data))==keccak256(abi.encode(y[i].topics,y[i].data)),"event data");
            require((x[i].emitter==address(a)&&y[i].emitter==address(b))||x[i].emitter==y[i].emitter,"event emitter");
        }
    }
    function write(uint slot,uint value) internal {tv.store(address(a),bytes32(slot),bytes32(value));tv.store(address(b),bytes32(slot),bytes32(value));}
    function mapped(uint key,uint root) internal pure returns(uint){return uint(keccak256(abi.encode(key,root)));}
    function checkWords(uint start,uint count) internal view {for(uint i;i<count;i++)require(tv.load(address(a),bytes32(start+i))==tv.load(address(b),bytes32(start+i)),"storage mismatch");}
    function checkState() internal view {
        checkWords(0,13);
        uint opened=uint(keccak256(abi.encode(address(this),address(0x123),uint(4))));
        uint[2] memory ids=[ID,opened];
        for(uint i;i<2;i++){checkWords(mapped(ids[i],3),1);checkWords(mapped(ids[i],4),2);checkWords(mapped(ids[i],10),3);checkWords(mapped(ids[i],11),1);}
        checkWords(mapped(uint160(address(this)),12),2);checkWords(mapped(uint160(BATCH),12),2);
    }
    function compare(bytes memory input) internal returns(bool){return compareAs(address(this),input);}
    function compareAs(address caller,bytes memory input) internal returns(bool){
        vm.recordLogs();vm.prank(caller);(bool x,bytes memory p)=address(a).call(input);PoolVm.Log[] memory logs=vm.getRecordedLogs();
        vm.recordLogs();vm.prank(caller);(bool y,bytes memory q)=address(b).call(input);logsEqual(logs,vm.getRecordedLogs());
        require(x==y,"success mismatch");require(keccak256(p)==keccak256(q),"return/revert mismatch");checkState();return x;
    }
    function seedBatch() internal {write(mapped(uint160(BATCH),12),uint(5e15)|(uint(25e17)<<128));write(mapped(uint160(BATCH),12)+1,3600);}
    function testOpenIndividualAndBatch() public {
        require(compare(abi.encodeCall(a.openTrove,(address(0x123),4,10e18,3000e18,11,12,5e16,100e18,address(0xaaa),address(0xbbb),address(0xccc)))));
        seedBatch();
        IBorrowerOperations.OpenTroveAndJoinInterestBatchManagerParams memory p=IBorrowerOperations.OpenTroveAndJoinInterestBatchManagerParams(address(0x123),4,10e18,3000e18,11,12,BATCH,100e18,address(0xaaa),address(0xbbb),address(0xccc));
        require(compare(abi.encodeCall(a.openTroveAndJoinInterestBatchManager,(p))));
    }
    function testAdjustmentsAndRepaymentCap() public {
        dep.configure(1,2000e18,false);
        require(compare(abi.encodeCall(a.addColl,(ID,1e18))));
        require(compare(abi.encodeCall(a.withdrawColl,(ID,1e18))));
        require(compare(abi.encodeCall(a.withdrawBold,(ID,100e18,100e18))));
        require(compare(abi.encodeCall(a.repayBold,(ID,type(uint).max))));
        require(compare(abi.encodeCall(a.adjustTrove,(ID,1e18,true,100e18,true,100e18))));
        write(mapped(ID,11),uint160(BATCH));
        require(compare(abi.encodeCall(a.adjustTrove,(ID,1e18,false,100e18,false,100e18))));
        dep.configure(4,2000e18,false);
        require(compare(abi.encodeCall(a.adjustZombieTrove,(ID,1e18,true,100e18,true,11,12,100e18))));
        require(compare(abi.encodeCall(a.applyPendingDebt,(ID,12,11))));
    }
    function testDelegatesBatchChangesAndClose() public {
        dep.configure(1,2000e18,false);seedBatch();
        require(compare(abi.encodeCall(a.setInterestIndividualDelegate,(ID,address(this),5e15,25e17,5e16,11,12,100e18,3600))));
        require(compare(abi.encodeCall(a.adjustTroveInterestRate,(ID,7e16,11,12,100e18))));
        require(compare(abi.encodeCall(a.setInterestBatchManager,(ID,BATCH,11,12,100e18))));
        require(compare(abi.encodeCall(a.removeFromBatch,(ID,5e16,11,12,100e18))));
        require(compare(abi.encodeCall(a.registerBatchManager,(5e15,25e17,5e16,1e16,3600))));
        require(compare(abi.encodeCall(a.lowerBatchManagementFee,(5e15))));
        require(compare(abi.encodeCall(a.setBatchManagerAnnualInterestRate,(7e16,11,12,100e18))));
        require(compare(abi.encodeCall(a.closeTrove,(ID))));
    }
    function testShutdownAndOracleFailure() public {
        require(!compare(abi.encodeCall(a.shutdown,())));
        dep.configure(1,100e18,false);
        require(compare(abi.encodeCall(a.shutdown,())));
        require(compare(abi.encodeCall(a.hasBeenShutDown,())));
        require(!compare(abi.encodeCall(a.addColl,(ID,1e18))));
        require(compare(abi.encodeCall(a.closeTrove,(ID))));
        require(!compare(abi.encodeCall(a.shutdown,())));
    }
    function testDependencyRollbackAndPermissionOrder() public {
        dep.configure(1,2000e18,true);
        require(!compare(abi.encodeCall(a.addColl,(ID,1e18))));
        dep.configure(0,2000e18,false);dep.setFail(true);
        require(!compare(abi.encodeCall(a.openTrove,(address(0x123),4,10e18,3000e18,11,12,5e16,100e18,address(0),address(0),address(0)))));
        require(!compare(abi.encodeCall(a.onLiquidateTrove,(ID))));
        require(!compare(abi.encodeCall(a.shutdownFromOracleFailure,())));
        require(!compare(abi.encodePacked(a.registerBatchManager.selector,uint(type(uint128).max)+1,uint(25e17),uint(5e16),uint(1e16),uint(3600))));
    }
    function testPrematureFeesDelegationAndBatchSwitch() public {
        dep.configure(1,2000e18,false);seedBatch();
        LatestTroveData memory t=dep.getLatestTroveData(ID);
        LatestBatchData memory bdata=dep.getLatestBatchData(BATCH);
        t.lastInterestRateAdjTime=block.timestamp-4000;bdata.lastInterestRateAdjTime=block.timestamp-4000;
        t.redistBoldDebtGain=10e18;t.redistCollGain=1e18;
        dep.setTroves(t,bdata);
        require(!compare(abi.encodeCall(a.adjustTroveInterestRate,(ID,7e16,11,12,0))));
        require(compare(abi.encodeCall(a.adjustTroveInterestRate,(ID,7e16,11,12,100e18))));
        require(compare(abi.encodeCall(a.registerBatchManager,(5e15,25e17,5e16,1e16,3600))));
        require(compare(abi.encodeCall(a.setBatchManagerAnnualInterestRate,(7e16,11,12,100e18))));
        require(compare(abi.encodeCall(a.setInterestBatchManager,(ID,BATCH,11,12,100e18))));
        require(compare(abi.encodeCall(a.switchBatchManager,(ID,11,12,address(this),13,14,100e18))));
        require(compare(abi.encodeCall(a.setInterestIndividualDelegate,(ID,address(this),5e15,25e17,8e16,11,12,100e18,5000))));
        require(!compare(abi.encodeCall(a.adjustTroveInterestRate,(ID,7e16,11,12,100e18))));
        require(compare(abi.encodeCall(a.removeInterestIndividualDelegate,(ID))));
    }
    function testKickAndPackedShutdown() public {
        dep.configure(4,2000e18,false);seedBatch();write(mapped(ID,11),uint160(BATCH));
        require(!compare(abi.encodeCall(a.kickFromBatch,(ID,11,12))));
        LatestTroveData memory t=dep.getLatestTroveData(ID);
        LatestBatchData memory bdata=dep.getLatestBatchData(BATCH);bdata.totalDebtShares=1;
        dep.setTroves(t,bdata);
        require(compare(abi.encodeCall(a.kickFromBatch,(ID,11,12))));
        write(9,uint160(address(dep))|(uint(0xabcdef)<<168));
        dep.configure(1,100e18,false);
        require(compare(abi.encodeCall(a.shutdown,())));
        require(compare(abi.encodeCall(a.hasBeenShutDown,())));
    }
    function testGettersAndManagerStorage() public {
        dep.configure(1,2000e18,false);
        require(compare(abi.encodeCall(a.CCR,())));require(compare(abi.encodeCall(a.MCR,())));
        require(compare(abi.encodeCall(a.SCR,())));require(compare(abi.encodeCall(a.BCR,())));
        require(compare(abi.encodeCall(a.activePool,())));
        require(compare(abi.encodeCall(a.getEntireBranchColl,())));require(compare(abi.encodeCall(a.getEntireBranchDebt,())));
        require(compare(abi.encodeCall(a.setAddManager,(ID,address(0xaaa)))));
        require(compare(abi.encodeCall(a.setRemoveManagerWithReceiver,(ID,address(0xbbb),address(0xccc)))));
        require(compare(abi.encodeCall(a.addManagerOf,(ID))));require(compare(abi.encodeCall(a.removeManagerReceiverOf,(ID))));
        require(compare(abi.encodeCall(a.setInterestIndividualDelegate,(ID,address(this),5e15,25e17,5e16,11,12,100e18,type(uint).max))));
        require(compare(abi.encodeCall(a.getInterestIndividualDelegateOf,(ID))));
        require(compare(abi.encodeCall(a.registerBatchManager,(5e15,25e17,5e16,1e16,3600))));
        require(compare(abi.encodeCall(a.getInterestBatchManager,(address(this)))));
        require(compare(abi.encodeCall(a.checkBatchManagerExists,(address(this)))));
        require(compare(abi.encodeCall(a.interestBatchManagerOf,(ID))));
        // Packed writes preserve bytes belonging to neighboring state.
        write(mapped(ID,10),uint160(address(this))|(uint(0xbeef)<<160));
        require(compare(abi.encodeCall(a.removeInterestIndividualDelegate,(ID))));
        write(5,uint160(address(this)));
        require(compare(abi.encodeCall(a.onLiquidateTrove,(ID))));
        write(5,uint160(address(dep)));
        write(2,uint160(address(this)));
        require(compare(abi.encodeCall(a.shutdownFromOracleFailure,())));
        require(compare(abi.encodeCall(a.shutdownFromOracleFailure,())));
    }
    function testManagerPermissionsAndWithdrawalReceiver() public {
        dep.configure(1,2000e18,false);address delegate=address(0xddd);address stranger=address(0xeee);
        require(compareAs(stranger,abi.encodeCall(a.addColl,(ID,1e18))));
        require(compare(abi.encodeCall(a.setAddManager,(ID,delegate))));
        require(!compareAs(stranger,abi.encodeCall(a.addColl,(ID,1e18))));
        require(compareAs(delegate,abi.encodeCall(a.addColl,(ID,1e18))));
        require(!compareAs(delegate,abi.encodeCall(a.withdrawColl,(ID,1e18))));
        require(compare(abi.encodeCall(a.setRemoveManagerWithReceiver,(ID,delegate,stranger))));
        require(compareAs(delegate,abi.encodeCall(a.withdrawColl,(ID,1e18))));
        require(compareAs(delegate,abi.encodeCall(a.withdrawBold,(ID,100e18,100e18))));
        require(compare(abi.encodeCall(a.setInterestIndividualDelegate,(ID,delegate,5e15,8e16,5e16,11,12,100e18,3600))));
        require(compareAs(delegate,abi.encodeCall(a.adjustTroveInterestRate,(ID,7e16,11,12,100e18))));
        require(!compareAs(delegate,abi.encodeCall(a.adjustTroveInterestRate,(ID,9e16,11,12,100e18))));
        require(!compareAs(stranger,abi.encodeCall(a.adjustTroveInterestRate,(ID,7e16,11,12,100e18))));
        require(compareAs(delegate,abi.encodeCall(a.closeTrove,(ID))));
    }
    function testMissingCodeAndMalformedArguments() public {
        bytes memory opening=abi.encodeCall(a.openTrove,(address(0x123),4,10e18,3000e18,11,12,5e16,100e18,address(0),address(0),address(0)));
        write(8,0xfeed);require(!compare(opening));write(8,uint160(address(dep)));
        write(9,0xfeed);require(!compare(opening));write(9,uint160(address(dep)));
        require(!compare(hex"010203"));
        bytes memory dirty=abi.encodePacked(a.openTrove.selector,uint(1)<<160,uint(4),uint(10e18),uint(3000e18),uint(11),uint(12),uint(5e16),uint(100e18),uint(0),uint(0),uint(0));
        require(!compare(dirty));
        require(!compare(abi.encodePacked(a.adjustTrove.selector,uint(ID),uint(1e18),uint(2),uint(0),uint(0),uint(0))));
        require(!compare(abi.encodePacked(a.openTroveAndJoinInterestBatchManager.selector,uint(0))));
    }
    function testFuzzOpening(uint128 coll,uint128 debt,uint128 rate,uint128 maxFee) public {
        compare(abi.encodeCall(a.openTrove,(address(0x123),4,uint(coll)%100e18,uint(debt)%10000e18,11,12,uint(rate)%26e17,uint(maxFee)%100e18,address(0),address(0),address(0))));
    }
    function testFuzzAdjustment(uint96 coll,uint96 debt,bool ci,bool di,bool batched) public {
        dep.configure(1,2000e18,false);if(batched)write(mapped(ID,11),uint160(BATCH));
        compare(abi.encodeCall(a.adjustTrove,(ID,uint(coll)%20e18,ci,uint(debt)%5000e18,di,type(uint).max)));
    }
}
