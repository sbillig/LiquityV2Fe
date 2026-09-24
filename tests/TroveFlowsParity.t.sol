// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {TroveManager,IAddressesRegistry,TroveChange} from "../reference/bold/contracts/src/TroveManager.sol";
import {ITroveManager} from "../reference/bold/contracts/src/Interfaces/ITroveManager.sol";
import {PoolVm} from "./DefaultPoolParity.t.sol";
import {TroveDataVm,EmptyTroveRegistry} from "./TroveDataParity.t.sol";
contract TroveFlowRegistry {
    address public WETH;
    constructor(address weth){WETH=weth;}
    function MCR() external pure returns(uint){return 11e17;}
    function LIQUIDATION_PENALTY_SP() external pure returns(uint){return 5e16;}
    function LIQUIDATION_PENALTY_REDISTRIBUTION() external pure returns(uint){return 1e17;}
    fallback() external {assembly{mstore(0,0) return(0,32)}}
}
contract TroveFlowDependency {
    event Called(bytes data);
    bool public fail;
    uint public price=2000e18;
    uint public last=2;
    uint public deposits=10000e18;
    function configure(uint p,uint l,uint d) external {price=p;last=l;deposits=d;}
    function fetchPrice() external returns(uint,bool){emit Called(msg.data);return(price,false);}
    function fetchRedemptionPrice() external returns(uint,bool){emit Called(msg.data);return(price,false);}
    function getLast() external view returns(uint){return last;}
    function getPrev(uint id) external pure returns(uint){return id>1?id-1:0;}
    function balanceOf(address) external pure returns(uint){return type(uint).max;}
    function getTotalBoldDeposits() external view returns(uint){return deposits;}
    function getBoldDebt() external pure returns(uint){return 1000e18;}
    function getCollBalance() external pure returns(uint){return 1000000e18;}
    function ownerOf(uint) external pure returns(address){return address(0x123);}
    function transferFrom(address,address,uint) external returns(bool){emit Called(msg.data);return true;}

    function setFail(bool value) external {fail=value;}
    fallback() external {require(!fail,"dependency failure");emit Called(msg.data);}
}
contract TroveFlowsParityTest {
    PoolVm constant vm=PoolVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    TroveDataVm constant tv=TroveDataVm(address(vm));
    TroveManager a;TroveManager b;TroveFlowDependency dep;
    address constant BATCH=address(0xba7c);
    function setUp() public {
        tv.warp(10_000_000_000);dep=new TroveFlowDependency();
        IAddressesRegistry registry=IAddressesRegistry(address(new TroveFlowRegistry(address(dep))));
        string memory artifacts=tv.envOr("LIQUITY_TEST_ARTIFACTS","build");
        if(keccak256(bytes(tv.envOr("LIQUITY_TROVE_MODULAR","true")))==keccak256("true")){
            address operations=deploy(artifacts,"TroveOperations","");
            address redemptions=deploy(artifacts,"TroveRedemptions","");
            address liquidations=deploy(artifacts,"TroveLiquidations",abi.encode(registry));
            a=TroveManager(deploy(artifacts,"TroveManager",abi.encode(registry,operations,redemptions,liquidations)));
        } else {
            bytes memory code=bytes.concat(vm.parseBytes(vm.readFile(string.concat(artifacts,"/TroveHookHarness.bin"))),abi.encode(address(this),address(dep),address(dep),address(dep)));
            address created;assembly{created:=create(0,add(code,32),mload(code))}require(created.code.length>0);a=TroveManager(created);
        }
        b=new TroveManager(registry);
        write(0,uint160(address(dep)));write(2,uint160(address(dep)));write(5,uint160(address(dep)));write(6,uint160(address(dep)));write(7,uint160(address(dep)));write(8,uint160(address(dep)));write(10,uint160(address(this)));write(25,uint160(address(dep)));write(1,uint160(address(dep)));write(3,uint160(address(dep)));write(4,uint160(address(this)));write(9,uint160(address(dep)));
    }
    function deploy(string memory path,string memory name,bytes memory args) internal returns(address created){
        bytes memory code=bytes.concat(vm.parseBytes(vm.readFile(string.concat(path,"/",name,".bin"))),args);
        require(code.length<=49152,"initcode limit");
        assembly{created:=create(0,add(code,32),mload(code))}
        require(created.code.length>0&&created.code.length<=24576,"runtime limit");
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

    function testRegularRedemptionAndZombieContinuation() public {
        open(1,false);open(2,false);
        require(compare(abi.encodeCall(a.redeemCollateral,(address(this),100e18,2000e18,5e15,1))));
        require(uint(tv.load(address(a),bytes32(uint(21))))==2);
        require(compare(abi.encodeCall(a.redeemCollateral,(address(this),3000e18,2000e18,5e15,0))));
        require(compare(abi.encodeCall(a.redeemCollateral,(address(this),0,2000e18,5e15,0))));
    }
    function testBatchRedemptionsAndSkippedICR() public {
        require(compare(abi.encodeCall(a.onRegisterBatchManager,(BATCH,5e16,1e16))));
        open(1,true);open(2,false);
        tv.warp(block.timestamp+365 days);
        require(compare(abi.encodeCall(a.redeemCollateral,(address(this),3000e18,2000e18,5e15,0))));
        require(compare(abi.encodeCall(a.redeemCollateral,(address(this),1000e18,1,5e15,0))));
    }
    function testUrgentRedemptionCapsAndRollback() public {
        open(1,false);open(2,true);write(24,block.timestamp);tv.warp(block.timestamp+365 days);
        uint[] memory ids=new uint[](4);ids[0]=99;ids[1]=1;ids[2]=2;ids[3]=1;
        dep.configure(100e18,2,10000e18);
        require(!compare(abi.encodeCall(a.urgentRedemption,(3000e18,ids,1000e18))));
        require(compare(abi.encodeCall(a.urgentRedemption,(3000e18,ids,0))));
        require(!compare(abi.encodeCall(a.urgentRedemption,(0,ids,0))));
    }
    function testLiquidationOffsetRedistributionAndSurplus() public {
        open(1,false);open(2,false);open(3,false);dep.configure(215e18,3,1001e18);
        write(4,uint160(address(dep)));uint[] memory ids=new uint[](1);ids[0]=2;
        require(compare(abi.encodeCall(a.batchLiquidateTroves,(ids))));
        dep.configure(100e18,3,0);ids[0]=1;
        require(compare(abi.encodeCall(a.batchLiquidateTroves,(ids))));
        ids[0]=3;require(!compare(abi.encodeCall(a.batchLiquidateTroves,(ids))));
    }
    function testBatchLiquidationAndNoEligibleTroves() public {
        open(1,false);open(2,true);open(3,false);dep.configure(215e18,3,10000e18);
        write(4,uint160(address(dep)));uint[] memory ids=new uint[](3);ids[0]=99;ids[1]=2;ids[2]=2;
        require(compare(abi.encodeCall(a.batchLiquidateTroves,(ids))));
        require(!compare(abi.encodeCall(a.batchLiquidateTroves,(ids))));
        ids=new uint[](0);require(!compare(abi.encodeCall(a.batchLiquidateTroves,(ids))));
    }
    function testFuzzRedemption(uint96 amount,uint64 price,uint64 rate,uint8 iterations,bool batch) public {
        open(1,false);open(2,batch);
        dep.configure(uint(price)+1,2,10000e18);
        compare(abi.encodeCall(a.redeemCollateral,(address(this),amount,uint(price)+1,uint(rate)%1e18,iterations)));
    }
    function testFuzzLiquidation(uint64 price,uint96 deposits,bool batch) public {
        open(1,false);open(2,batch);open(3,false);
        dep.configure(uint(price)*100+1,3,deposits);
        write(4,uint160(address(dep)));uint[] memory ids=new uint[](2);ids[0]=2;ids[1]=3;
        compare(abi.encodeCall(a.batchLiquidateTroves,(ids)));
    }

    function testManagerGettersAndShutdown() public {
        // This test exercises the complete public manager rather than the isolated harness.
        if(keccak256(bytes(tv.envOr("LIQUITY_TROVE_MODULAR","true")))!=keccak256("true"))return;
        open(1,false);open(2,true);
        require(compare(abi.encodeCall(a.getLatestTroveData,(1))));
        require(compare(abi.encodeCall(a.getLatestBatchData,(BATCH))));
        require(compare(abi.encodeCall(a.getCurrentICR,(2,2000e18))));
        require(compare(abi.encodeCall(a.getTroveAnnualInterestRate,(2))));
        require(compare(abi.encodeCall(a.getTroveStatus,(1))));
        require(compare(abi.encodeCall(a.getTroveIdsCount,())));
        require(compare(abi.encodeCall(a.getTroveFromTroveIdsArray,(0))));
        require(!compare(abi.encodeCall(a.getTroveFromTroveIdsArray,(2))));
        require(compare(abi.encodeWithSignature("Troves(uint256)",1)));
        require(compare(abi.encodeWithSignature("rewardSnapshots(uint256)",1)));
        require(compare(abi.encodeCall(a.getEntireBranchColl,())));
        require(compare(abi.encodeCall(a.getEntireBranchDebt,())));
        require(compare(abi.encodeCall(a.getUnbackedPortionPriceAndRedeemability,())));
        require(compare(abi.encodeCall(a.shutdown,())));
        require(compare(abi.encodeCall(a.shutdownTime,())));
        require(compare(abi.encodeCall(a.getUnbackedPortionPriceAndRedeemability,())));
        require(compare(abi.encodeCall(a.CCR,())));
    }

    function testManagerConstructorEventsAndStorage() public {
        if(keccak256(bytes(tv.envOr("LIQUITY_TROVE_MODULAR","true")))!=keccak256("true"))return;
        IAddressesRegistry registry=IAddressesRegistry(address(new TroveFlowRegistry(address(dep))));
        string memory path=tv.envOr("LIQUITY_TEST_ARTIFACTS","build");
        address operations=deploy(path,"TroveOperations","");
        address redemptions=deploy(path,"TroveRedemptions","");
        address liquidations=deploy(path,"TroveLiquidations",abi.encode(registry));
        vm.recordLogs();address ca=deploy(path,"TroveManager",abi.encode(registry,operations,redemptions,liquidations));
        PoolVm.Log[] memory x=vm.getRecordedLogs();
        vm.recordLogs();address cb=address(new TroveManager(registry));PoolVm.Log[] memory y=vm.getRecordedLogs();
        require(x.length==11&&x.length==y.length,"constructor events");
        for(uint i;i<x.length;i++)require(keccak256(abi.encode(x[i].topics,x[i].data))==keccak256(abi.encode(y[i].topics,y[i].data))&&x[i].emitter==ca&&y[i].emitter==cb);
        for(uint i;i<25;i++)require(tv.load(ca,bytes32(i))==tv.load(cb,bytes32(i)),"constructor storage");
        require(TroveManager(ca).CCR()==TroveManager(cb).CCR());
        require(address(TroveManager(ca).activePool())==address(TroveManager(cb).activePool()));
    }

    function testMalformedAbiAndPermissionOrder() public {
        TroveChange memory c;c.debtIncrease=2000e18;c.collIncrease=10e18;
        bytes memory encoded=abi.encodeCall(a.onOpenTrove,(address(this),1,c,5e16));
        assembly{mstore(add(encoded,36),shl(160,1))}
        require(!compare(encoded));
        write(4,123);require(!compare(encoded));
        require(!compare(abi.encodeCall(a.onOpenTrove,(address(this),1,c,5e16))));
        require(!compare(abi.encodePacked(a.urgentRedemption.selector,uint256(1),uint256(96),uint256(0),uint256(2),uint256(1))));
        require(!compare(abi.encodePacked(a.batchLiquidateTroves.selector,uint256(32),type(uint256).max)));
        require(!compare(abi.encodePacked(a.batchLiquidateTroves.selector,uint256(32),uint256(0x7fffffffffffffb))));
        require(!compare(abi.encodePacked(a.batchLiquidateTroves.selector,uint256(32),uint256(type(uint64).max))));
        require(!compare(hex"010203"));
    }
}
