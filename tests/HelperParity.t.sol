// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {HintHelpers,ICollateralRegistry,LatestTroveData,LatestBatchData,TroveChange} from "../reference/bold/contracts/src/HintHelpers.sol";
import {DebtInFrontHelper} from "../reference/bold/contracts/src/DebtInFrontHelper.sol";
import {IHintHelpers} from "../reference/bold/contracts/src/Interfaces/IHintHelpers.sol";
import {Constants} from "../reference/bold/contracts/src/Dependencies/Constants.sol";
import {MultiTroveGetter} from "../reference/bold/contracts/src/MultiTroveGetter.sol";
interface HelperVm {
    function readFile(string calldata) external view returns(string memory);
    function parseBytes(string calldata) external pure returns(bytes memory);
    function warp(uint) external;
}
contract HelperDependencies {
    uint public count=5;
    address public batch=address(0xba7c);
    uint public adjusted=1000;
    bool public fail;
    function set(uint c,address b,uint time,bool f) external {count=c;batch=b;adjusted=time;fail=f;}
    function getTroveManager(uint i) external view returns(address){require(!fail,"dependency failure");return i==0?address(this):address(0);}
    function activePool() external view returns(address){return address(this);}
    function sortedTroves() external view returns(address){return address(this);}
    function getTroveIdsCount() external view returns(uint){return count;}
    function getSize() external view returns(uint){return count;}
    function getTroveFromTroveIdsArray(uint index) external pure returns(uint){return index+1;}
    function getLast() external view returns(uint){return count==0?0:5;}
    function getFirst() external view returns(uint){return count==0?0:1;}
    function getNext(uint id) external pure returns(uint){return id<5?id+1:0;}
    function getPrev(uint id) external pure returns(uint){return id>1?id-1:0;}
    function contains(uint id) external pure returns(bool){return id!=3&&id>0&&id<=5;}
    function getTroveAnnualInterestRate(uint id) external pure returns(uint){return (6-id)*1e16;}
    function findInsertPosition(uint rate,uint,uint) external pure returns(uint,uint){for(uint id=5;id>0;id--){if((6-id)*1e16>=rate)return(id,id==5?0:id+1);}return(0,1);}
    function nodes(uint id) external view returns(uint,uint,address,bool){return(id<5?id+1:0,id>1?id-1:0,batch,id>0&&id<=5);}
    function getLatestTroveData(uint id) external view returns(LatestTroveData memory t){
        t.entireDebt=3000e18+id;t.entireColl=10e18+id;t.redistBoldDebtGain=3e18;t.redistCollGain=1e18;t.accruedInterest=4e18;t.recordedDebt=2900e18;t.annualInterestRate=(6-id)*1e16;t.weightedRecordedDebt=2900e18*t.annualInterestRate;t.accruedBatchManagementFee=5e18;t.lastInterestRateAdjTime=adjusted;
    }
    function getLatestBatchData(address) external view returns(LatestBatchData memory b){b.entireDebtWithoutRedistribution=10000e18;b.annualInterestRate=6e16;b.weightedRecordedDebt=9500e18*6e16;b.accruedManagementFee=5e18;b.lastInterestRateAdjTime=adjusted;}
    function Troves(uint id) external view returns(uint,uint,uint,uint8,uint64,uint64,uint64,uint,address,uint){uint[10] memory v;v[0]=2900e18;v[1]=9e18;v[2]=7e18;v[3]=1;v[4]=uint64(id);v[5]=800;v[6]=uint64(adjusted);v[7]=(6-id)*1e16;v[8]=uint160(batch);v[9]=123e18;assembly{return(v,320)}}
    function rewardSnapshots(uint id) external pure returns(uint,uint){return(id*111,id*222);}
    function getNewApproxAvgInterestRateFromTroveChange(TroveChange calldata c) external pure returns(uint){return uint(keccak256(abi.encode(c)))%1e17;}
}
contract HelperParityTest {
    HelperVm constant vm=HelperVm(address(uint160(uint(keccak256("hevm cheat code")))));
    HelperDependencies dep;HintHelpers a;HintHelpers b;MultiTroveGetter x;MultiTroveGetter y;
    function deploy(string memory name) internal returns(address created){bytes memory init=bytes.concat(vm.parseBytes(vm.readFile(string.concat("build/",name,".bin"))),abi.encode(dep));assembly{created:=create(0,add(init,32),mload(init))}require(created.code.length>0&&created.code.length<=24576);}
    function setUp() public {vm.warp(2000);dep=new HelperDependencies();a=HintHelpers(deploy("HintHelpers"));b=new HintHelpers(ICollateralRegistry(address(dep)));x=MultiTroveGetter(deploy("MultiTroveGetter"));y=new MultiTroveGetter(ICollateralRegistry(address(dep)));}
    function compare(address actual,address expected,bytes memory data,uint gasLimit) internal returns(bool){(bool ok,bytes memory p)=actual.call{gas:gasLimit}(data);(bool success,bytes memory q)=expected.call{gas:gasLimit}(data);require(ok==success,"success");require(keccak256(p)==keccak256(q),"return/revert");return ok;}
    function hint(bytes memory data) internal returns(bool){return compare(address(a),address(b),data,5000000);}
    function getter(bytes memory data) internal returns(bool){return compare(address(x),address(y),data,5000000);}
    function debtHelpers() internal returns(DebtInFrontHelper d,DebtInFrontHelper e){
        bytes memory init=bytes.concat(vm.parseBytes(vm.readFile("build/DebtInFrontHelper.bin")),abi.encode(dep,a));
        address created;assembly{created:=create(0,add(init,32),mload(init))}require(created.code.length>0);d=DebtInFrontHelper(created);
        e=new DebtInFrontHelper(ICollateralRegistry(address(dep)),IHintHelpers(address(b)));
    }
    function testLegacyConstants() public {
        Constants actual=Constants(deploy("Constants"));Constants expected=new Constants();
        require(actual._MIN_DEBT()==expected._MIN_DEBT());
        require(actual._ETH_GAS_COMPENSATION()==expected._ETH_GAS_COMPENSATION());
    }
    function testDebtRangesAndExcludedTrove() public {
        (DebtInFrontHelper d,DebtInFrontHelper e)=debtHelpers();
        for(uint lo=0;lo<7;lo++)for(uint hi=0;hi<7;hi++){
            require(compare(address(d),address(e),abi.encodeCall(d.getDebtBetweenInterestRates,(0,lo*1e16,hi*1e16,3,2,0)),5000000));
            require(compare(address(d),address(e),abi.encodeCall(d.getDebtBetweenInterestRateAndTrove,(0,lo*1e16,hi*1e16,3,2,10)),5000000));
        }
    }
    function testDebtHintsSignedOverflowAndInvalidIndex() public {
        (DebtInFrontHelper d,DebtInFrontHelper e)=debtHelpers();
        require(!compare(address(d),address(e),abi.encodeCall(d.getDebtBetweenInterestRates,(1,0,6e16,0,0,0)),5000000));
        require(!compare(address(d),address(e),abi.encodeCall(d.getDebtBetweenInterestRates,(0,uint(1)<<255,type(uint).max,0,1,1)),5000000));
        require(compare(address(d),address(e),abi.encodeCall(d.getDebtBetweenInterestRates,(0,type(uint).max,type(uint).max,0,1,1)),5000000));
    }
    function testAllFeePredictionsAndCooldown() public {
        require(hint(abi.encodeCall(a.NAME,())));require(hint(abi.encodeCall(a.collateralRegistry,())));
        for(uint i;i<2;i++){
            dep.set(5,i==0?address(0):address(0xba7c),1000,false);
            require(hint(abi.encodeCall(a.predictOpenTroveUpfrontFee,(0,3000e18,5e16))));
            require(hint(abi.encodeCall(a.predictAdjustInterestRateUpfrontFee,(0,1,5e16))));
            require(hint(abi.encodeCall(a.forcePredictAdjustInterestRateUpfrontFee,(0,1,5e16))));
            require(hint(abi.encodeCall(a.predictAdjustTroveUpfrontFee,(0,1,100e18))));
            require(hint(abi.encodeCall(a.predictAdjustBatchInterestRateUpfrontFee,(0,address(0xba7c),5e16))));
            require(hint(abi.encodeCall(a.predictOpenTroveAndJoinBatchUpfrontFee,(0,3000e18,address(0xba7c)))));
            require(hint(abi.encodeCall(a.predictJoinBatchInterestRateUpfrontFee,(0,1,address(0xba7c)))));
            require(hint(abi.encodeCall(a.predictRemoveFromBatchUpfrontFee,(0,1,5e16))));
        }
        vm.warp(1000+7 days);require(hint(abi.encodeCall(a.predictAdjustInterestRateUpfrontFee,(0,1,5e16))));
        require(hint(abi.encodeCall(a.predictAdjustBatchInterestRateUpfrontFee,(0,address(0xba7c),5e16))));
        require(hint(abi.encodeCall(a.predictRemoveFromBatchUpfrontFee,(0,1,5e16))));
    }
    function testSortedPaginationAndPaddedDebtResults() public {
        for(int i=-7;i<7;i++)for(uint n=0;n<8;n++)require(getter(abi.encodeCall(x.getMultipleSortedTroves,(0,i,n))));
        require(getter(abi.encodeCall(x.getMultipleSortedTroves,(0,type(int).min,type(uint).max))));
        for(uint i=0;i<7;i++)for(uint n=0;n<8;n++)require(getter(abi.encodeCall(x.getDebtPerInterestRateAscending,(0,i,n))));
    }
    function testInvalidIndexAndZeroDebtShortCircuit() public {
        require(!getter(abi.encodeCall(x.getMultipleSortedTroves,(1,0,1))));require(!getter(abi.encodeCall(x.getDebtPerInterestRateAscending,(1,0,1))));
        dep.set(0,address(0),1000,false);require(hint(abi.encodeCall(a.getApproxHint,(0,5e16,100,123))));
        dep.set(0,address(0),1000,true);require(hint(abi.encodeCall(a.predictAdjustTroveUpfrontFee,(0,1,0))));
        require(!hint(abi.encodeCall(a.predictAdjustTroveUpfrontFee,(0,1,1))));
    }
    function testHugeAllocationPanic() public {
        uint n=uint(type(uint64).max)+8;
        dep.set(type(uint).max,address(0),1000,false);
        for(uint i=0;i<16;i++){
            compare(address(x),address(y),abi.encodeCall(x.getMultipleSortedTroves,(0,0,n-i)),100000);
            compare(address(x),address(y),abi.encodeCall(x.getDebtPerInterestRateAscending,(0,0,n-i)),100000);
        }
        compare(address(x),address(y),abi.encodeCall(x.getDebtPerInterestRateAscending,(0,0,type(uint).max)),100000);
    }
    function testFuzzHints(uint128 rate,uint8 trials,uint seed) public {require(hint(abi.encodeCall(a.getApproxHint,(0,uint(rate),uint(trials)%40,seed))));}
    function testFuzzFees(uint128 amount,uint128 rate) public {hint(abi.encodeCall(a.predictOpenTroveUpfrontFee,(0,uint(amount),uint(rate))));hint(abi.encodeCall(a.predictAdjustTroveUpfrontFee,(0,1,uint(amount))));}
}
