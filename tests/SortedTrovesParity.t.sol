// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {SortedTroves} from "../reference/bold/contracts/src/SortedTroves.sol";
import {BatchId} from "../reference/bold/contracts/src/Types/BatchId.sol";
import {IAddressesRegistry} from "../reference/bold/contracts/src/Interfaces/IAddressesRegistry.sol";
import {PoolVm} from "./DefaultPoolParity.t.sol";
interface StorageVm {function load(address,bytes32) external view returns(bytes32);}
contract RateManagerMock {
    mapping(uint256=>uint256) public rates;
    bool public fail;
    function setRate(uint256 id,uint256 value) external {rates[id]=value;}
    function setFail(bool value) external {fail=value;}
    function getTroveAnnualInterestRate(uint256 id) external view returns(uint256) {require(!fail,"rate unavailable");return rates[id];}
}
contract SortedRegistryMock {
    address public troveManager;
    address public borrowerOperations;
    constructor(address manager,address bo){troveManager=manager;borrowerOperations=bo;}
}
contract SortedTrovesParityTest {
    PoolVm constant vm=PoolVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    SortedTroves a;SortedTroves b;RateManagerMock manager;
    uint256 constant N=16;
    function setUp() public {
        manager=new RateManagerMock();SortedRegistryMock reg=new SortedRegistryMock(address(manager),address(this));
        bytes memory code=bytes.concat(vm.parseBytes(vm.readFile("build/SortedTroves.bin")),abi.encode(reg));
        vm.recordLogs();address deployed;assembly{deployed:=create(0,add(code,32),mload(code))}
        require(deployed.code.length>0,"Fe deployment");a=SortedTroves(deployed);
        PoolVm.Log[] memory x=vm.getRecordedLogs();vm.recordLogs();b=new SortedTroves(IAddressesRegistry(address(reg)));
        PoolVm.Log[] memory y=vm.getRecordedLogs();require(x.length==y.length);
        for(uint i;i<x.length;i++)require(keccak256(abi.encode(x[i].topics,x[i].data))==keccak256(abi.encode(y[i].topics,y[i].data)),"constructor events");
    }
    function batch(uint256 n) internal pure returns(BatchId){return BatchId.wrap(address(uint160(n)));}
    function compare(address caller,bytes memory data) internal returns(bool) {
        vm.prank(caller);(bool okA,bytes memory x)=address(a).call(data);
        vm.prank(caller);(bool okB,bytes memory y)=address(b).call(data);
        require(okA==okB,"success mismatch");require(keccak256(x)==keccak256(y),"return/revert mismatch");
        sameState();return okA;
    }
    function sameView(bytes memory data) internal view {
        (bool okA,bytes memory x)=address(a).staticcall(data);(bool okB,bytes memory y)=address(b).staticcall(data);
        require(okA==okB,"view success");require(keccak256(x)==keccak256(y),"view result");
    }
    function nodeEqual(uint256 id) internal view {
        sameView(abi.encodeCall(a.nodes,(id)));sameView(abi.encodeCall(a.contains,(id)));
        sameView(abi.encodeCall(a.isBatchedNode,(id)));sameView(abi.encodeCall(a.getNext,(id)));sameView(abi.encodeCall(a.getPrev,(id)));
        bytes32 slot=keccak256(abi.encode(id,uint256(1)));
        for(uint256 i;i<3;i++) {
            bytes32 at;unchecked{at=bytes32(uint256(slot)+i);}
            require(StorageVm(address(vm)).load(address(a),at)==StorageVm(address(vm)).load(address(b),at),"node storage layout");
        }
    }
    function sameState() internal view {
        require(a.size()==b.size()&&a.getSize()==b.getSize(),"size");require(a.isEmpty()==b.isEmpty(),"empty");
        require(a.getFirst()==b.getFirst()&&a.getLast()==b.getLast(),"endpoints");
        require(StorageVm(address(vm)).load(address(a),0)==StorageVm(address(vm)).load(address(b),0),"size layout");
        for(uint256 id;id<=N;id++)nodeEqual(id);
        for(uint256 k;k<=4;k++) {
            sameView(abi.encodeCall(a.batches,(batch(k))));sameView(abi.encodeCall(a.isEmptyBatch,(batch(k))));
            bytes32 slot=keccak256(abi.encode(address(uint160(k)),uint256(2)));
            require(StorageVm(address(vm)).load(address(a),slot)==StorageVm(address(vm)).load(address(b),slot),"batch head layout");
            unchecked{slot=bytes32(uint256(slot)+1);}
            require(StorageVm(address(vm)).load(address(a),slot)==StorageVm(address(vm)).load(address(b),slot),"batch tail layout");
        }
    }
    function invariants() internal view {
        uint256 previous;uint256 id=a.getFirst();uint256 count;uint256 lastRate=type(uint256).max;
        uint256 seen;address previousBatch;uint256 closedBatches;
        while(id!=0) {
            require(count++<N,"cycle");require(a.contains(id),"missing linked node");
            require(a.getPrev(id)==previous,"back link");
            uint256 rate=manager.rates(id);require(rate<=lastRate,"rate ordering");lastRate=rate;
            require(id<=N&&seen&(1<<id)==0,"duplicate node");seen|=1<<id;
            (, ,BatchId group,)=a.nodes(id);address current=BatchId.unwrap(group);
            if(current!=previousBatch) {
                if(previousBatch!=address(0))closedBatches|=1<<uint160(previousBatch);
                if(current!=address(0)) {
                    require(closedBatches&(1<<uint160(current))==0,"split batch");
                    (uint256 head,)=a.batches(group);require(head==id,"batch head");
                }
            }
            uint256 next=a.getNext(id);
            if(current!=address(0)) {
                (,,BatchId nextBatch,)=a.nodes(next);
                if(BatchId.unwrap(nextBatch)!=current) { (,uint256 tail)=a.batches(group);require(tail==id,"batch tail"); }
            }
            previousBatch=current;previous=id;id=next;
        }
        require(count==a.size()&&previous==a.getLast(),"size/last");
        require(!a.contains(0),"root existence");
    }
    function insert(uint256 id,uint256 rate,uint256 group,uint256 p,uint256 n) internal {
        manager.setRate(id,rate);
        bytes memory data=group==0?abi.encodeCall(a.insert,(id,rate,p,n)):abi.encodeCall(a.insertIntoBatch,(id,batch(group),rate,p,n));
        require(compare(address(this),data),"insert failed");
    }
    function updateBatch(uint256 group,uint256 rate) internal {
        for(uint256 id=1;id<=N;id++) { (,,BatchId g,)=a.nodes(id);if(BatchId.unwrap(g)==address(uint160(group)))manager.setRate(id,rate); }
    }
    function testGettersAndEmptyPositions() public {
        sameView(abi.encodeCall(a.NAME,()));sameView(abi.encodeCall(a.troveManager,()));sameView(abi.encodeCall(a.borrowerOperationsAddress,()));
        sameView(abi.encodeCall(a.findInsertPosition,(uint256(0),uint256(17),uint256(18))));
        sameView(abi.encodeCall(a.validInsertPosition,(uint256(0),uint256(0),uint256(0))));sameState();invariants();
    }
    function testEqualRatesAndBatchOrder() public {
        insert(1,5,0,0,0);insert(2,5,1,0,0);insert(3,5,1,999,999);insert(4,5,0,0,0);insert(5,5,2,0,0);
        require(a.getFirst()==1&&a.getNext(1)==2&&a.getNext(2)==3&&a.getNext(3)==4&&a.getNext(4)==5);
        require(!a.validInsertPosition(5,2,3));
        require(compare(address(this),abi.encodeCall(a.reInsertBatch,(batch(1),uint256(5),uint256(2),uint256(3)))));
        invariants();
    }
    function testBatchHeadTailMiddleAndSingletonRemoval() public {
        insert(1,6,0,0,0);insert(2,5,1,0,0);insert(3,5,1,0,0);insert(4,5,1,0,0);insert(5,5,1,0,0);insert(6,4,0,0,0);
        require(compare(address(manager),abi.encodeCall(a.removeFromBatch,(uint256(3)))));invariants();
        require(compare(address(this),abi.encodeCall(a.removeFromBatch,(uint256(2)))));invariants();
        require(compare(address(manager),abi.encodeCall(a.removeFromBatch,(uint256(5)))));invariants();
        require(compare(address(this),abi.encodeCall(a.removeFromBatch,(uint256(4)))));invariants();require(a.isEmptyBatch(batch(1)));
        insert(7,3,1,0,0);invariants();
    }
    function testReinsertWholeBatchesAndNodes() public {
        insert(1,9,0,0,0);insert(2,7,1,0,0);insert(3,7,1,0,0);insert(4,5,2,0,0);insert(5,5,2,0,0);insert(6,3,0,0,0);
        updateBatch(1,1);require(compare(address(this),abi.encodeCall(a.reInsertBatch,(batch(1),uint256(1),uint256(2),uint256(3)))));invariants();
        updateBatch(1,10);require(compare(address(this),abi.encodeCall(a.reInsertBatch,(batch(1),uint256(10),uint256(999),uint256(998)))));invariants();
        manager.setRate(6,6);require(compare(address(this),abi.encodeCall(a.reInsert,(uint256(6),uint256(6),uint256(4),uint256(5)))));invariants();
        // Also cover the protocol order where the old rate is visible during reinsertion.
        require(compare(address(this),abi.encodeCall(a.reInsert,(uint256(1),uint256(0),uint256(0),uint256(0)))));manager.setRate(1,0);invariants();
    }
    function testFuzzStatefulSequence(uint256 seed) public {
        for(uint256 step;step<24;step++) {
            seed=uint256(keccak256(abi.encode(seed,step)));
            uint256 id=1+seed%N;uint256 operation=(seed>>8)%6;uint256 rate=(seed>>16)%10;
            uint256 p=(seed>>32)%(N+4);uint256 n=(seed>>40)%(N+4);uint256 group=1+(seed>>48)%4;
            bytes memory data;
            if(operation==0) {
                if(!a.contains(id))manager.setRate(id,rate);
                data=abi.encodeCall(a.insert,(id,rate,p,n));
            } else if(operation==1) {
                (uint256 head,)=a.batches(batch(group));if(head!=0)rate=manager.rates(head);
                if(!a.contains(id))manager.setRate(id,rate);
                data=abi.encodeCall(a.insertIntoBatch,(id,batch(group),rate,p,n));
            } else if(operation==2) data=abi.encodeCall(a.remove,(id));
            else if(operation==3) data=abi.encodeCall(a.removeFromBatch,(id));
            else if(operation==4) {
                // BorrowerOperations updates the manager only after reinsertion.
                data=abi.encodeCall(a.reInsert,(id,rate,p,n));
            } else {
                data=abi.encodeCall(a.reInsertBatch,(batch(group),rate,p,n));
            }
            bool success=compare(address(this),data);
            if(success&&operation==4)manager.setRate(id,rate);
            if(success&&operation==5)updateBatch(group,rate);
            invariants();
            sameView(abi.encodeCall(a.findInsertPosition,(rate,p,n)));
            sameView(abi.encodeCall(a.validInsertPosition,(rate,p,n)));
        }
    }
    function testRateUpdateOrderingRegression() public {
        // This sequence detects a test harness that updates the manager's rate
        // before reinsertion, unlike the real BorrowerOperations contract.
        testFuzzStatefulSequence(615696399558502200651263363728009872212221276);
    }
    function testFuzzHints(uint256 rate,uint256 p,uint256 n) public {
        insert(1,10,0,0,0);insert(2,8,1,0,0);insert(3,8,1,0,0);insert(4,4,2,0,0);insert(5,4,2,0,0);insert(6,1,0,0,0);
        p%=20;n%=20;
        sameView(abi.encodeCall(a.findInsertPosition,(rate,p,n)));sameView(abi.encodeCall(a.validInsertPosition,(rate,p,n)));
        insert(7,rate,0,p,n);invariants();
    }
    function testErrorsAndAuthorization() public {
        compare(address(this),abi.encodeCall(a.insert,(uint256(0),uint256(1),uint256(0),uint256(0))));
        compare(address(this),abi.encodeCall(a.insertIntoBatch,(uint256(0),batch(1),uint256(1),uint256(0),uint256(0))));
        compare(address(this),abi.encodeCall(a.insertIntoBatch,(uint256(1),batch(0),uint256(1),uint256(0),uint256(0))));
        insert(1,5,0,0,0);insert(2,4,1,0,0);
        compare(address(this),abi.encodeCall(a.remove,(uint256(2))));compare(address(this),abi.encodeCall(a.removeFromBatch,(uint256(1))));
        compare(address(this),abi.encodeCall(a.reInsert,(uint256(2),uint256(6),uint256(0),uint256(0))));
        address[2] memory callers=[address(0xbeef),address(manager)];
        for(uint i;i<2;i++) {
            compare(callers[i],abi.encodeCall(a.insert,(uint256(3),uint256(5),uint256(0),uint256(0))));
            compare(callers[i],abi.encodeCall(a.insertIntoBatch,(uint256(3),batch(2),uint256(5),uint256(0),uint256(0))));
            compare(callers[i],abi.encodeCall(a.reInsert,(uint256(1),uint256(5),uint256(0),uint256(0))));
            compare(callers[i],abi.encodeCall(a.reInsertBatch,(batch(1),uint256(5),uint256(0),uint256(0))));
        }
        compare(address(0xbeef),abi.encodeCall(a.remove,(uint256(1))));compare(address(0xbeef),abi.encodeCall(a.removeFromBatch,(uint256(2))));
    }
    function testManagerFailureRollsBackAndWideIds() public {
        insert(1,5,0,0,0);manager.setRate(2,4);manager.setFail(true);
        require(!compare(address(this),abi.encodeCall(a.insert,(uint256(2),uint256(4),uint256(0),uint256(0)))));
        manager.setFail(false);insert(type(uint256).max,6,0,0,0);nodeEqual(type(uint256).max);
        require(compare(address(manager),abi.encodeCall(a.remove,(type(uint256).max))));nodeEqual(type(uint256).max);invariants();
    }
}
