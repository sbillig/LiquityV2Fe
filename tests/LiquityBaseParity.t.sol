// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {LiquityBase,IAddressesRegistry,IActivePool,IDefaultPool} from "../reference/bold/contracts/src/Dependencies/LiquityBase.sol";
import {PoolVm} from "./DefaultPoolParity.t.sol";
import {StorageVm} from "./SortedTrovesParity.t.sol";
interface BaseEnvVm {function envOr(string calldata,string calldata) external returns(string memory);}
contract BranchPoolMock {
    uint256 coll;uint256 debt;bool failColl;bool failDebt;
    function set(uint256 c,uint256 d,bool fc,bool fd) external {coll=c;debt=d;failColl=fc;failDebt=fd;}
    function getCollBalance() external view returns(uint256){require(!failColl,"coll failed");return coll;}
    function getBoldDebt() external view returns(uint256){require(!failDebt,"debt failed");return debt;}
}
contract BaseRegistryMock {
    address public activePool;address public defaultPool;address public constant priceFeed=address(0xfeed);
    constructor(address a,address d){activePool=a;defaultPool=d;}
}
contract LiquityBaseReferenceHarness is LiquityBase {
    constructor(IAddressesRegistry registry) LiquityBase(registry) {}
    function tcr(address a,address d,uint256 price) external returns(uint256){activePool=IActivePool(a);defaultPool=IDefaultPool(d);return _getTCR(price);}
    function below(address a,address d,uint256 price,uint256 ccr) external returns(bool){activePool=IActivePool(a);defaultPool=IDefaultPool(d);return _checkBelowCriticalThreshold(price,ccr);}
}
contract LiquityBaseParityTest {
    PoolVm constant vm=PoolVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    BranchPoolMock active;BranchPoolMock default_;LiquityBase a;LiquityBase b;LiquityBaseReferenceHarness ha;LiquityBaseReferenceHarness hb;
    function deploy(string memory name,bytes memory args) internal returns(address created){bytes memory code=bytes.concat(vm.parseBytes(vm.readFile(string.concat(BaseEnvVm(address(vm)).envOr("LIQUITY_TEST_ARTIFACTS","build"),"/",name,".bin"))),args);assembly{created:=create(0,add(code,32),mload(code))}require(created.code.length>0);}
    function setUp() public {
        active=new BranchPoolMock();default_=new BranchPoolMock();BaseRegistryMock registry=new BaseRegistryMock(address(active),address(default_));
        vm.recordLogs();a=LiquityBase(deploy("LiquityBase",abi.encode(registry)));PoolVm.Log[] memory x=vm.getRecordedLogs();
        vm.recordLogs();b=new LiquityBase(IAddressesRegistry(address(registry)));PoolVm.Log[] memory y=vm.getRecordedLogs();require(x.length==y.length);
        for(uint i;i<x.length;i++)require(keccak256(abi.encode(x[i].topics,x[i].data))==keccak256(abi.encode(y[i].topics,y[i].data)));
        ha=LiquityBaseReferenceHarness(deploy("LiquityBaseHarness",hex""));hb=new LiquityBaseReferenceHarness(IAddressesRegistry(address(registry)));
    }
    function compare(address x,address y,bytes memory data) internal { (bool p,bytes memory r)=x.call(data);(bool q,bytes memory s)=y.call(data);require(p==q&&keccak256(r)==keccak256(s),"outcome"); }
    function testConstructorStorageAndGetters() public {
        require(address(a.activePool())==address(b.activePool()));
        for(uint i;i<3;i++)require(StorageVm(address(vm)).load(address(a),bytes32(i))==StorageVm(address(vm)).load(address(b),bytes32(i)),"storage");
        compare(address(a),address(b),abi.encodeCall(a.getEntireBranchColl,()));compare(address(a),address(b),abi.encodeCall(a.getEntireBranchDebt,()));
    }
    function testFuzzTotalsAndRatios(uint256 ac,uint256 ad,uint256 dc,uint256 dd,uint256 price,uint256 ccr) public {
        active.set(ac,ad,false,false);default_.set(dc,dd,false,false);
        compare(address(a),address(b),abi.encodeCall(a.getEntireBranchColl,()));compare(address(a),address(b),abi.encodeCall(a.getEntireBranchDebt,()));
        compare(address(ha),address(hb),abi.encodeCall(ha.tcr,(address(active),address(default_),price)));
        compare(address(ha),address(hb),abi.encodeCall(ha.below,(address(active),address(default_),price,ccr)));
    }
    function testDependencyFailures() public {
        for(uint m;m<16;m++) {
            active.set(10,20,m&1!=0,m&2!=0);default_.set(30,40,m&4!=0,m&8!=0);
            compare(address(a),address(b),abi.encodeCall(a.getEntireBranchColl,()));compare(address(a),address(b),abi.encodeCall(a.getEntireBranchDebt,()));
            compare(address(ha),address(hb),abi.encodeCall(ha.tcr,(address(active),address(default_),uint256(100))));
        }
    }
    function testThresholdBoundaryAndZeroDebt() public {
        active.set(2e18,1e18,false,false);default_.set(0,1e18,false,false);
        compare(address(ha),address(hb),abi.encodeCall(ha.below,(address(active),address(default_),uint256(1e18),uint256(1e18))));
        compare(address(ha),address(hb),abi.encodeCall(ha.below,(address(active),address(default_),uint256(1e18),uint256(1e18+1))));
        active.set(type(uint256).max,0,false,false);default_.set(0,0,false,false);
        compare(address(ha),address(hb),abi.encodeCall(ha.tcr,(address(active),address(default_),type(uint256).max)));
    }
}
