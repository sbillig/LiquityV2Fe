// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {CollateralRegistry, IBoldToken, ITroveManager, IERC20Metadata} from "../reference/bold/contracts/src/CollateralRegistry.sol";
import {BoldToken} from "../reference/bold/contracts/src/BoldToken.sol";
import {PoolVm} from "./DefaultPoolParity.t.sol";
interface RegistryTestVm {
    function envOr(string calldata,string calldata) external returns(string memory);
    function warp(uint256) external;
    function load(address,bytes32) external view returns(bytes32);
    function store(address,bytes32,bytes32) external;
}
contract RedemptionTokenMock {
    uint256 public rawSupply=1_000_000e18;
    function totalSupply() external view returns(uint256){require(!failSupply,"supply failed");return rawSupply;}
    mapping(address=>uint256) public burned;
    bool public failSupply;bool public failBurn;
    function set(uint256 supply,bool supplyFailure,bool burnFailure) external {rawSupply=supply;failSupply=supplyFailure;failBurn=burnFailure;}
    function burn(address account,uint256 amount) external {require(!failBurn,"burn failed");rawSupply-=amount;burned[account]+=amount;}
}
contract RedemptionBranchMock {
    uint256 public unbacked;uint256 public price;uint256 public debt;bool public redeemable=true;
    uint256 public cap=type(uint256).max;uint256 public failure;uint256 public observations;
    uint256 public attempts;uint256 public lastAmount;uint256 public lastPrice;uint256 public lastRate;uint256 public lastIterations;address public lastRedeemer;
    bool public secondDisabled;
    event Redemption(address redeemer,uint256 amount,uint256 price,uint256 rate,uint256 iterations);
    function set(uint256 u,uint256 p,uint256 d,bool enabled,uint256 limit,uint256 fail,bool second) external {
        unbacked=u;price=p;debt=d;redeemable=enabled;cap=limit;failure=fail;secondDisabled=second;observations=0;
    }
    function getUnbackedPortionPriceAndRedeemability() external returns(uint256,uint256,bool) {
        require(failure!=1,"unbacked failed");observations++;
        return(unbacked,price,redeemable&&!(secondDisabled&&observations%2==0));
    }
    function getEntireBranchDebt() external view returns(uint256){require(failure!=2,"debt failed");return debt;}
    function redeemCollateral(address redeemer,uint256 amount,uint256 p,uint256 rate,uint256 iterations) external returns(uint256){
        require(failure!=3,"redeem failed");attempts++;lastAmount=amount;lastPrice=p;lastRate=rate;lastIterations=iterations;lastRedeemer=redeemer;
        emit Redemption(redeemer,amount,p,rate,iterations);return amount<cap?amount:cap;
    }
}
contract CollateralRegistryParityTest {
    PoolVm constant vm=PoolVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    RegistryTestVm constant rv=RegistryTestVm(address(vm));
    CollateralRegistry a;CollateralRegistry b;RedemptionTokenMock ta;RedemptionTokenMock tb;
    RedemptionBranchMock[3] ma;RedemptionBranchMock[3] mb;
    address constant USER=address(0xa11ce);
    function feCode() internal returns(bytes memory){return vm.parseBytes(vm.readFile(string.concat(rv.envOr("LIQUITY_TEST_ARTIFACTS","build"),"/CollateralRegistry.bin")));}
    function deploy(bytes memory code,bytes memory args) internal returns(address result,bytes memory failure){
        bytes memory init=bytes.concat(code,args);
        assembly{result:=create(0,add(init,32),mload(init)) let n:=returndatasize() failure:=mload(64) mstore(failure,n) returndatacopy(add(failure,32),0,n) mstore(64,add(add(failure,32),and(add(n,31),not(31))))}
    }
    function logsEqual(PoolVm.Log[] memory x,PoolVm.Log[] memory y) internal pure {
        require(x.length==y.length,"log count");for(uint i;i<x.length;i++)require(keccak256(abi.encode(x[i].topics,x[i].data))==keccak256(abi.encode(y[i].topics,y[i].data)),"logs");
    }
    function setUp() public {
        rv.warp(1_000_001);ta=new RedemptionTokenMock();tb=new RedemptionTokenMock();
        IERC20Metadata[] memory tokens=new IERC20Metadata[](3);ITroveManager[] memory am=new ITroveManager[](3);ITroveManager[] memory bm=new ITroveManager[](3);
        for(uint i;i<3;i++){tokens[i]=IERC20Metadata(address(uint160(100+i)));ma[i]=new RedemptionBranchMock();mb[i]=new RedemptionBranchMock();am[i]=ITroveManager(address(ma[i]));bm[i]=ITroveManager(address(mb[i]));}
        vm.recordLogs();(address created,)=deploy(feCode(),abi.encode(ta,tokens,am));require(created.code.length>0);a=CollateralRegistry(created);PoolVm.Log[] memory x=vm.getRecordedLogs();
        vm.recordLogs();b=new CollateralRegistry(IBoldToken(address(tb)),tokens,bm);logsEqual(x,vm.getRecordedLogs());
        configure(0,10e18,2000e18,100e18,true,type(uint256).max,0,false);
        configure(1,20e18,1500e18,300e18,true,type(uint256).max,0,false);
        configure(2,30e18,1700e18,600e18,true,type(uint256).max,0,false);
    }
    function configure(uint i,uint u,uint p,uint d,bool enabled,uint cap,uint fail,bool second) internal {ma[i].set(u,p,d,enabled,cap,fail,second);mb[i].set(u,p,d,enabled,cap,fail,second);}
    function compare(bytes memory data) internal returns(bool){
        vm.recordLogs();vm.prank(USER);(bool x,bytes memory p)=address(a).call(data);PoolVm.Log[] memory logs=vm.getRecordedLogs();
        vm.recordLogs();vm.prank(USER);(bool y,bytes memory q)=address(b).call(data);logsEqual(logs,vm.getRecordedLogs());
        require(x==y,"success mismatch");require(keccak256(p)==keccak256(q),"return/revert mismatch");stateEqual();return x;
    }
    function stateEqual() internal view {
        for(uint i;i<2;i++)require(rv.load(address(a),bytes32(i))==rv.load(address(b),bytes32(i)),"registry storage");
        require(ta.rawSupply()==tb.rawSupply()&&ta.burned(USER)==tb.burned(USER),"token state");
        for(uint i;i<3;i++){
            require(ma[i].observations()==mb[i].observations()&&ma[i].attempts()==mb[i].attempts(),"branch calls");
            require(ma[i].lastAmount()==mb[i].lastAmount()&&ma[i].lastPrice()==mb[i].lastPrice()&&ma[i].lastRate()==mb[i].lastRate()&&ma[i].lastIterations()==mb[i].lastIterations()&&ma[i].lastRedeemer()==mb[i].lastRedeemer(),"branch args");
        }
    }
    function constructorCase(bytes memory args) internal returns(bool) {
        vm.recordLogs();(address x,bytes memory p)=deploy(feCode(),args);PoolVm.Log[] memory logs=vm.getRecordedLogs();
        vm.recordLogs();(address y,bytes memory q)=deploy(type(CollateralRegistry).creationCode,args);logsEqual(logs,vm.getRecordedLogs());
        require((x!=address(0))==(y!=address(0)),"constructor success mismatch");
        if(x==address(0)){require(keccak256(p)==keccak256(q),"constructor revert mismatch");return false;}
        CollateralRegistry first=CollateralRegistry(x);CollateralRegistry second=CollateralRegistry(y);
        require(first.totalCollaterals()==second.totalCollaterals()&&address(first.boldToken())==address(second.boldToken()));
        for(uint i;i<10;i++){require(address(first.getToken(i))==address(second.getToken(i)));require(address(first.getTroveManager(i))==address(second.getTroveManager(i)));}
        for(uint i;i<2;i++)require(rv.load(x,bytes32(i))==rv.load(y,bytes32(i)),"constructor storage");
        return true;
    }
    function constructorArgs(uint tokenCount,uint managerCount) internal view returns(bytes memory) {
        address[] memory tokens=new address[](tokenCount);address[] memory managers=new address[](managerCount);
        for(uint i;i<tokenCount;i++)tokens[i]=address(uint160(i+100));for(uint i;i<managerCount;i++)managers[i]=address(uint160(i+200));
        return abi.encode(ta,tokens,managers);
    }
    function testConstructorLengthsAndUnusedSlots() public {
        require(!constructorCase(constructorArgs(0,0)));require(!constructorCase(constructorArgs(11,11)));
        for(uint i=1;i<=10;i++){require(constructorCase(constructorArgs(i,i)));require(constructorCase(constructorArgs(i,i+1)));require(!constructorCase(constructorArgs(i,i-1)));}
    }
    function testConstructorMalformedAddressElements() public {
        bytes memory args=constructorArgs(1,2);
        assembly{let offset:=mload(add(args,96)) mstore(add(add(args,offset),96),not(0))}
        require(!constructorCase(args));
        args=constructorArgs(11,11);
        assembly{let offset:=mload(add(args,64)) mstore(add(add(args,offset),384),not(0))}
        require(!constructorCase(args));
        args=constructorArgs(1,1);assembly{mstore(add(args,32),not(0))}require(!constructorCase(args));
    }
    function testSupplyFailureAndFeeLimitOrdering() public {
        ta.set(1_000_000e18,true,false);tb.set(1_000_000e18,true,false);
        require(!compare(abi.encodeCall(a.getRedemptionRateForRedeemedAmount,(1))));require(!compare(abi.encodeCall(a.getEffectiveRedemptionFeeInBold,(1))));require(!compare(abi.encodeCall(a.redeemCollateral,(1,1,1e18))));
        ta.set(0,false,false);tb.set(0,false,false);require(!compare(abi.encodeCall(a.redeemCollateral,(1,1,1e18))));
        ta.set(1_000_000e18,false,false);tb.set(1_000_000e18,false,false);
        require(!compare(abi.encodeCall(a.redeemCollateral,(1,1,5e15))));
        rv.warp(block.timestamp+365 days);require(compare(abi.encodeCall(a.redeemCollateral,(1,1,6e15))));
    }
    function testGettersAndMinuteDecay() public {
        require(a.totalCollaterals()==3&&b.totalCollaterals()==3);require(address(a.boldToken())==address(ta)&&address(b.boldToken())==address(tb));
        for(uint i;i<10;i++) {require(address(a.getToken(i))==address(b.getToken(i)));require(address(a.getTroveManager(i))==(i<3?address(ma[i]):address(0)));require(address(b.getTroveManager(i))==(i<3?address(mb[i]):address(0)));}
        require(!compare(abi.encodeCall(a.getToken,(10))));require(!compare(abi.encodeCall(a.getTroveManager,(type(uint).max))));
        uint[6] memory offsets=[uint(0),59,60,61,3600,60*525600001];
        for(uint i;i<offsets.length;i++){rv.warp(1_000_001+offsets[i]);require(compare(abi.encodeCall(a.getRedemptionRateWithDecay,())));require(compare(abi.encodeCall(a.getRedemptionFeeWithDecay,(123e18))));require(compare(abi.encodeCall(a.getEffectiveRedemptionFeeInBold,(123e18))));}
        rv.warp(1);require(!compare(abi.encodeCall(a.getRedemptionRateWithDecay,())));
    }
    function testAllocationTruncationAndRounding() public {
        require(compare(abi.encodeCall(a.redeemCollateral,(100e18,7,1e18))));
        require(ta.burned(USER)==60e18&&ma[0].lastAmount()==10e18&&ma[1].lastAmount()==20e18&&ma[2].lastAmount()==30e18);
        for(uint i;i<3;i++)configure(i,1,100+i,100,true,type(uint).max,0,false);
        require(compare(abi.encodeCall(a.redeemCollateral,(2,99,1e18))));
        require(ma[0].lastAmount()==10e18&&ma[1].lastAmount()==1&&ma[2].lastAmount()==1,"remainder allocation");
    }
    function testFallbackAndActualRedemptionAccounting() public {
        rv.warp(block.timestamp+3600);
        configure(0,0,10,100,true,3,0,false);configure(1,0,20,300,true,7,0,false);configure(2,0,30,600,false,type(uint).max,0,false);
        require(compare(abi.encodeCall(a.redeemCollateral,(200,4,1e18))));
        require(ma[0].lastAmount()==50&&ma[1].lastAmount()==150&&ma[2].attempts()==0);require(ta.burned(USER)==10);
        require(a.lastFeeOperationTime()==1_003_601);uint last=a.lastFeeOperationTime();
        rv.warp(block.timestamp+59);require(compare(abi.encodeCall(a.redeemCollateral,(1,4,1e18))));require(a.lastFeeOperationTime()==last);
        rv.warp(block.timestamp+2);require(compare(abi.encodeCall(a.redeemCollateral,(1,4,1e18))));require(a.lastFeeOperationTime()==last+60);
    }
    function testDependencyErrorsRollbackAndZeroBranches() public {
        configure(0,1,1,1,true,type(uint).max,1,false);
        require(!compare(abi.encodeCall(a.redeemCollateral,(0,0,0))));require(!compare(abi.encodeCall(a.redeemCollateral,(0,0,1e18))));require(!compare(abi.encodeCall(a.redeemCollateral,(1,0,1e18))));
        for(uint i;i<3;i++)configure(i,0,i+1,10,true,type(uint).max,i==1?2:0,false);
        require(!compare(abi.encodeCall(a.redeemCollateral,(1,0,1e18))));
        for(uint i;i<3;i++)configure(i,10,i+1,10,true,type(uint).max,i==2?3:0,false);
        require(!compare(abi.encodeCall(a.redeemCollateral,(30,0,1e18))));
        for(uint i;i<3;i++)configure(i,10,i+1,10,true,type(uint).max,0,false);
        ta.set(1_000_000e18,false,true);tb.set(1_000_000e18,false,true);require(!compare(abi.encodeCall(a.redeemCollateral,(30,0,1e18))));
        ta.set(1_000_000e18,false,false);tb.set(1_000_000e18,false,false);
        for(uint i;i<3;i++)configure(i,0,i+1,10,true,type(uint).max,0,true);
        require(compare(abi.encodeCall(a.redeemCollateral,(30,0,1e18))));require(ta.burned(USER)==0);
    }
    function testFuzzRedemptionAllocation(uint128 x,uint128 y,uint128 z,uint128 requested,uint32 elapsed,uint8 flags,uint128 cap) public {
        rv.warp(block.timestamp+elapsed);
        uint[3] memory debt=[uint(x),uint(y),uint(z)];
        for(uint i;i<3;i++)configure(i,(flags&8)==0?debt[i]:0,100+i,debt[i],flags&(1<<i)==0,cap,0,false);
        ta.set(type(uint128).max,false,false);tb.set(type(uint128).max,false,false);
        compare(abi.encodeCall(a.redeemCollateral,(uint(requested),uint(flags),1e18)));
    }
    function testConnectedRealBoldTokenBurnAndRollback() public {
        bytes memory boldCode=vm.parseBytes(vm.readFile(string.concat(rv.envOr("LIQUITY_TEST_ARTIFACTS","build"),"/BoldToken.bin")));
        (address boldAddress,)=deploy(boldCode,abi.encode(address(this)));require(boldAddress.code.length>0);
        BoldToken firstToken=BoldToken(boldAddress);BoldToken secondToken=new BoldToken(address(this));
        IERC20Metadata[] memory tokens=new IERC20Metadata[](1);tokens[0]=IERC20Metadata(address(100));
        ITroveManager[] memory firstManagers=new ITroveManager[](1);firstManagers[0]=ITroveManager(address(ma[0]));
        ITroveManager[] memory secondManagers=new ITroveManager[](1);secondManagers[0]=ITroveManager(address(mb[0]));
        (address firstAddress,)=deploy(feCode(),abi.encode(firstToken,tokens,firstManagers));require(firstAddress.code.length>0);
        CollateralRegistry first=CollateralRegistry(firstAddress);CollateralRegistry second=new CollateralRegistry(IBoldToken(address(secondToken)),tokens,secondManagers);
        firstToken.setBranchAddresses(address(ma[0]),address(123),address(this),address(this));secondToken.setBranchAddresses(address(mb[0]),address(123),address(this),address(this));
        firstToken.setCollateralRegistry(address(first));secondToken.setCollateralRegistry(address(second));
        firstToken.mint(USER,5e18);secondToken.mint(USER,5e18);firstToken.mint(address(987),495e18);secondToken.mint(address(987),495e18);
        rv.warp(block.timestamp+1 days);
        for(uint attempt;attempt<2;attempt++) {
            if(attempt==1){firstToken.mint(USER,45e18);secondToken.mint(USER,45e18);}
            bytes memory data=abi.encodeCall(first.redeemCollateral,(20e18,17,1e18));
            vm.recordLogs();vm.prank(USER);(bool x,bytes memory p)=address(first).call(data);PoolVm.Log[] memory logs=vm.getRecordedLogs();
            vm.recordLogs();vm.prank(USER);(bool y,bytes memory q)=address(second).call(data);logsEqual(logs,vm.getRecordedLogs());
            require(x==y&&x==(attempt==1)&&keccak256(p)==keccak256(q),"connected burn outcome");
            require(firstToken.totalSupply()==secondToken.totalSupply()&&firstToken.balanceOf(USER)==secondToken.balanceOf(USER));
            for(uint i;i<2;i++)require(rv.load(address(first),bytes32(i))==rv.load(address(second),bytes32(i)),"connected rollback");
            require(ma[0].observations()==mb[0].observations()&&ma[0].attempts()==mb[0].attempts());
            if(attempt==0){require(ma[0].attempts()==0&&first.lastFeeOperationTime()==1_000_001);}
        }
        require(firstToken.balanceOf(USER)==40e18&&firstToken.totalSupply()==535e18);
        require(firstToken.allowance(USER,address(first))==0,"registry burn needs no allowance");
    }
    function testFuzzRedemptionSequence(uint256 seed) public {
        for(uint step;step<12;step++) {
            seed=uint256(keccak256(abi.encode(seed,step)));rv.warp(block.timestamp+seed%181);
            for(uint i;i<3;i++) {
                uint value=uint256(keccak256(abi.encode(seed,i)));
                configure(i,(seed&8)==0?value%1e21:0,1e18+i,value%3e21,(value&3)!=0,value%1e20,0,false);
            }
            require(compare(abi.encodeCall(a.redeemCollateral,(1+seed%1e20,seed%100,1e18))));
        }
    }
    function testFuzzFeeArithmetic(uint256 amount,uint256 supply,uint256 base,uint64 elapsed) public {
        ta.set(supply,false,false);tb.set(supply,false,false);rv.store(address(a),bytes32(0),bytes32(base));rv.store(address(b),bytes32(0),bytes32(base));rv.warp(block.timestamp+elapsed);
        compare(abi.encodeCall(a.getRedemptionRate,()));compare(abi.encodeCall(a.getRedemptionRateWithDecay,()));compare(abi.encodeCall(a.getRedemptionRateForRedeemedAmount,(amount)));compare(abi.encodeCall(a.getRedemptionFeeWithDecay,(amount)));compare(abi.encodeCall(a.getEffectiveRedemptionFeeInBold,(amount)));
    }
}
