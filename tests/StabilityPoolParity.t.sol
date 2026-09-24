// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {StabilityPool,IAddressesRegistry} from "../reference/bold/contracts/src/StabilityPool.sol";
import {BoldToken} from "../reference/bold/contracts/src/BoldToken.sol";
import {PoolVm} from "./DefaultPoolParity.t.sol";
import {ActiveCollateralToken} from "./ActivePoolParity.t.sol";
interface SPTestVm {
    function envOr(string calldata,string calldata) external returns(string memory);
    function load(address,bytes32) external view returns(bytes32);
    function store(address,bytes32,bytes32) external;
}
contract SPActiveMock {
    BoldToken public bold;ActiveCollateralToken public coll;StabilityPool public pool;
    uint256 public pending;uint256 public mintCalls;bool public failMint;bool public failSend;bool public failPending;
    constructor(BoldToken b,ActiveCollateralToken c){bold=b;coll=c;}
    function setPool(StabilityPool p) external {pool=p;}
    function setPending(uint256 value) external {pending=value;}
    function failures(bool m,bool s,bool p) external {failMint=m;failSend=s;failPending=p;}
    function mintAggInterest() external {
        require(!failMint,"interest failed");mintCalls++;uint256 value=pending;pending=0;
        if(value!=0){bold.mint(address(pool),value);pool.triggerBoldRewards(value);}
    }
    function calcPendingSPYield() external view returns(uint256){require(!failPending,"pending failed");return pending;}
    function sendColl(address to,uint256 amount) external {require(msg.sender==address(pool));require(!failSend,"send failed");require(coll.transfer(to,amount));}
    function getCollBalance() external view returns(uint256){return coll.balanceOf(address(this));}
    function getBoldDebt() external pure returns(uint256){return 1e25;}
}
contract SPDefaultMock {
    function getCollBalance() external pure returns(uint256){return 0;}
    function getBoldDebt() external pure returns(uint256){return 0;}
}
contract SPRegistryMock {
    address public activePool;address public defaultPool;address public priceFeed=address(0xfeed);
    address public collToken;address public troveManager;address public boldToken;
    constructor(address a,address d,address c,address tm,address b){activePool=a;defaultPool=d;collToken=c;troveManager=tm;boldToken=b;}
}
contract StabilityPoolParityTest {
    PoolVm constant vm=PoolVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    SPTestVm constant sv=SPTestVm(address(vm));
    StabilityPool a;StabilityPool b;BoldToken ba;BoldToken bb;ActiveCollateralToken ca;ActiveCollateralToken cb;SPActiveMock aa;SPActiveMock ab;SPDefaultMock defaults;
    address constant ALICE=address(0xa11ce);address constant BOB=address(0xb0b);address constant CAROL=address(0xca401);address constant MANAGER=address(0x7111);
    function deploy(string memory name,bytes memory args) internal returns(address created){
        bytes memory code=bytes.concat(vm.parseBytes(vm.readFile(string.concat(sv.envOr("LIQUITY_TEST_ARTIFACTS","build"),"/",name,".bin"))),args);
        require(code.length<=49152,"initcode limit");assembly{created:=create(0,add(code,32),mload(code))}require(created.code.length>0&&created.code.length<=24576,"deployment");
    }
    function setUp() public {
        ba=BoldToken(deploy("BoldToken",abi.encode(address(this))));bb=new BoldToken(address(this));
        ca=new ActiveCollateralToken();cb=new ActiveCollateralToken();aa=new SPActiveMock(ba,ca);ab=new SPActiveMock(bb,cb);defaults=new SPDefaultMock();
        SPRegistryMock ra=new SPRegistryMock(address(aa),address(defaults),address(ca),MANAGER,address(ba));
        SPRegistryMock rb=new SPRegistryMock(address(ab),address(defaults),address(cb),MANAGER,address(bb));
        vm.recordLogs();a=StabilityPool(deploy("StabilityPool",abi.encode(ra)));PoolVm.Log[] memory x=vm.getRecordedLogs();
        vm.recordLogs();b=new StabilityPool(IAddressesRegistry(address(rb)));logsEqual(x,vm.getRecordedLogs());
        aa.setPool(a);ab.setPool(b);
        ba.setBranchAddresses(MANAGER,address(a),address(this),address(aa));bb.setBranchAddresses(MANAGER,address(b),address(this),address(ab));
        ca.mint(address(aa),1e30);cb.mint(address(ab),1e30);
        address[3] memory users=[ALICE,BOB,CAROL];for(uint i;i<3;i++){ba.mint(users[i],1e30);bb.mint(users[i],1e30);}
    }
    function normalized(bytes32 word) internal view returns(bytes32){
        if(word==bytes32(uint256(uint160(address(a)))))return bytes32(uint256(uint160(address(b))));
        if(word==bytes32(uint256(uint160(address(aa)))))return bytes32(uint256(uint160(address(ab))));
        if(word==bytes32(uint256(uint160(address(ba)))))return bytes32(uint256(uint160(address(bb))));
        if(word==bytes32(uint256(uint160(address(ca)))))return bytes32(uint256(uint160(address(cb))));
        return word;
    }
    function logsEqual(PoolVm.Log[] memory x,PoolVm.Log[] memory y) internal view {
        require(x.length==y.length,"log count");for(uint i;i<x.length;i++){
            require(normalized(bytes32(uint256(uint160(x[i].emitter))))==bytes32(uint256(uint160(y[i].emitter))),"emitter");
            require(x[i].topics.length==y[i].topics.length&&x[i].data.length==y[i].data.length,"log shape");
            for(uint j;j<x[i].topics.length;j++)require(normalized(x[i].topics[j])==y[i].topics[j],"topics");
            for(uint j;j<x[i].data.length;j+=32){bytes32 p;bytes32 q;bytes memory first=x[i].data;bytes memory second=y[i].data;assembly{p:=mload(add(add(first,32),j)) q:=mload(add(add(second,32),j))}require(normalized(p)==q,"log data");}
        }
    }
    function compare(address user,bytes memory data) internal returns(bool){
        address other=user==address(aa)?address(ab):user;
        vm.recordLogs();vm.prank(user);(bool x,bytes memory p)=address(a).call(data);PoolVm.Log[] memory logs=vm.getRecordedLogs();
        vm.recordLogs();vm.prank(other);(bool y,bytes memory q)=address(b).call(data);logsEqual(logs,vm.getRecordedLogs());
        require(x==y,"success mismatch");require(keccak256(p)==keccak256(q),"return/revert mismatch");stateEqual();return x;
    }
    function sameView(bytes memory data) internal view {
        (bool x,bytes memory p)=address(a).staticcall(data);(bool y,bytes memory q)=address(b).staticcall(data);
        require(x==y&&keccak256(p)==keccak256(q),"getter");
    }
    function stateEqual() internal view {
        for(uint i;i<14;i++)require(normalized(sv.load(address(a),bytes32(i)))==sv.load(address(b),bytes32(i)),"scalar storage");
        require(ba.totalSupply()==bb.totalSupply()&&ba.balanceOf(address(a))==bb.balanceOf(address(b)),"BOLD balance");
        require(ca.balanceOf(address(a))==cb.balanceOf(address(b))&&ca.balanceOf(address(aa))==cb.balanceOf(address(ab)),"coll balance");
        require(aa.pending()==ab.pending()&&aa.mintCalls()==ab.mintCalls(),"interest calls");
        require(ba.balanceOf(address(a))==a.getTotalBoldDeposits()+a.getYieldGainsOwed()+a.getYieldGainsPending(),"BOLD conservation");
        require(ca.balanceOf(address(a))==a.getCollBalance(),"coll conservation");
        address[3] memory users=[ALICE,BOB,CAROL];for(uint i;i<3;i++){
            address user=users[i];require(ba.balanceOf(user)==bb.balanceOf(user)&&ca.balanceOf(user)==cb.balanceOf(user),"user balances");
            for(uint root=7;root<=9;root++){bytes32 slot=keccak256(abi.encode(user,root));uint count=root==8?4:1;for(uint j;j<count;j++)require(sv.load(address(a),bytes32(uint(slot)+j))==sv.load(address(b),bytes32(uint(slot)+j)),"user storage");}
            sameView(abi.encodeCall(a.depositSnapshots,(user)));sameView(abi.encodeCall(a.deposits,(user)));sameView(abi.encodeCall(a.stashedColl,(user)));
            sameView(abi.encodeCall(a.getDepositorCollGain,(user)));sameView(abi.encodeCall(a.getDepositorYieldGain,(user)));sameView(abi.encodeCall(a.getCompoundedBoldDeposit,(user)));sameView(abi.encodeCall(a.getDepositorYieldGainWithPending,(user)));
        }
        uint scale=a.currentScale();for(uint i;i<=scale+2&&i<20;i++){require(a.scaleToS(i)==b.scaleToS(i)&&a.scaleToB(i)==b.scaleToB(i),"reward sums");}
    }
    function pending(uint value) internal {aa.setPending(value);ab.setPending(value);}
    function testConstructorGettersAndPermissions() public {
        stateEqual();require(address(a.collToken())==address(ca)&&address(a.boldToken())==address(ba)&&address(a.troveManager())==MANAGER&&address(a.activePool())==address(aa));
        sameView(abi.encodeCall(a.NAME,()));sameView(abi.encodeCall(a.P_PRECISION,()));sameView(abi.encodeCall(a.SCALE_FACTOR,()));sameView(abi.encodeCall(a.SCALE_SPAN,()));sameView(abi.encodeCall(a.MAX_SCALE_FACTOR_EXPONENT,()));
        sameView(abi.encodeCall(a.getEntireBranchColl,()));sameView(abi.encodeCall(a.getEntireBranchDebt,()));
        require(!compare(ALICE,abi.encodeCall(a.offset,(0,0))));require(!compare(ALICE,abi.encodeCall(a.triggerBoldRewards,(1))));
        require(!compare(ALICE,abi.encodeCall(a.provideToSP,(0,false))));require(!compare(ALICE,abi.encodeCall(a.withdrawFromSP,(0,false))));require(!compare(ALICE,abi.encodeCall(a.claimAllCollGains,())));
    }
    function testDepositYieldClaimsAndCompounding() public {
        require(compare(ALICE,abi.encodeCall(a.provideToSP,(100e18,false))));pending(10e18);
        sameView(abi.encodeCall(a.getDepositorYieldGainWithPending,(ALICE)));
        require(compare(BOB,abi.encodeCall(a.provideToSP,(100e18,true))));require(a.getDepositorYieldGain(ALICE)==10e18);
        pending(20e18);require(compare(ALICE,abi.encodeCall(a.withdrawFromSP,(10e18,false))));require(a.deposits(ALICE)==110e18);
        require(compare(MANAGER,abi.encodeCall(a.offset,(21e18,3e18))));
        require(compare(BOB,abi.encodeCall(a.withdrawFromSP,(0,true))));require(ca.balanceOf(BOB)>0&&a.stashedColl(BOB)==0);
        require(compare(ALICE,abi.encodeCall(a.provideToSP,(1e18,false))));require(a.stashedColl(ALICE)>0);
        require(compare(ALICE,abi.encodeCall(a.withdrawFromSP,(type(uint256).max,false))));require(a.deposits(ALICE)==0&&a.stashedColl(ALICE)>0);
        require(compare(ALICE,abi.encodeCall(a.claimAllCollGains,())));require(a.stashedColl(ALICE)==0);
        require(!compare(BOB,abi.encodeCall(a.withdrawFromSP,(type(uint256).max,true))));
    }
    function testPendingYieldThresholdAndMinimumWithdrawal() public {
        pending(3e18);require(compare(ALICE,abi.encodeCall(a.provideToSP,(5e17,false))));require(a.getYieldGainsPending()==3e18&&a.getYieldGainsOwed()==0);
        require(compare(BOB,abi.encodeCall(a.provideToSP,(5e17,false))));require(a.getYieldGainsPending()==0&&a.getYieldGainsOwed()==3e18);
        require(a.getDepositorYieldGain(ALICE)==15e17&&a.getDepositorYieldGain(BOB)==15e17);
        require(compare(ALICE,abi.encodeCall(a.withdrawFromSP,(0,false))));require(a.getTotalBoldDeposits()==25e17);
        require(compare(ALICE,abi.encodeCall(a.withdrawFromSP,(15e17,true))));require(a.getTotalBoldDeposits()==1e18);
        require(!compare(BOB,abi.encodeCall(a.withdrawFromSP,(1,true))));require(compare(BOB,abi.encodeCall(a.withdrawFromSP,(0,true))));
    }
    function testDependencyRollbackAndErrors() public {
        aa.failures(true,false,false);ab.failures(true,false,false);require(!compare(ALICE,abi.encodeCall(a.provideToSP,(1e18,false))));
        aa.failures(false,false,false);ab.failures(false,false,false);require(compare(ALICE,abi.encodeCall(a.provideToSP,(10e18,false))));
        require(!compare(ALICE,abi.encodeCall(a.provideToSP,(type(uint).max,false))));
        aa.failures(false,true,false);ab.failures(false,true,false);require(!compare(MANAGER,abi.encodeCall(a.offset,(1e18,1e18))));
        aa.failures(false,false,false);ab.failures(false,false,false);require(compare(MANAGER,abi.encodeCall(a.offset,(1e18,1e18))));
        ca.setFail(true);cb.setFail(true);require(!compare(ALICE,abi.encodeCall(a.withdrawFromSP,(0,true))));
        ca.setFail(false);cb.setFail(false);require(compare(ALICE,abi.encodeCall(a.withdrawFromSP,(0,true))));
        require(!compare(MANAGER,abi.encodeCall(a.offset,(a.getTotalBoldDeposits(),0))));require(!compare(MANAGER,abi.encodeCall(a.offset,(type(uint).max,1))));
    }
    function mintInterest() internal {
        vm.recordLogs();aa.mintAggInterest();PoolVm.Log[] memory logs=vm.getRecordedLogs();
        vm.recordLogs();ab.mintAggInterest();logsEqual(logs,vm.getRecordedLogs());stateEqual();
    }
    function testScaleTransitionsAndExpiredDeposits() public {
        ba.mint(ALICE,1e40);bb.mint(ALICE,1e40);ba.mint(CAROL,5e40);bb.mint(CAROL,5e40);
        require(compare(ALICE,abi.encodeCall(a.provideToSP,(1e40,false))));pending(1e20);mintInterest();
        for(uint i;i<4;i++) {
            if(i!=0)require(compare(CAROL,abi.encodeCall(a.provideToSP,(1e40,false))));
            uint total=a.getTotalBoldDeposits();require(compare(MANAGER,abi.encodeCall(a.offset,(total-1e18,2e18))));
            require(a.currentScale()>i,"expected scale transition");
            pending(1e18);mintInterest();
        }
        require(a.currentScale()>8&&a.getCompoundedBoldDeposit(ALICE)==0,"expired deposit");
        require(compare(ALICE,abi.encodeCall(a.withdrawFromSP,(0,true))));require(a.deposits(ALICE)==0);
    }
    function testProductZeroAndOverflowBoundaries() public {
        ba.mint(ALICE,1e60);bb.mint(ALICE,1e60);require(compare(ALICE,abi.encodeCall(a.provideToSP,(1e60,false))));
        require(!compare(MANAGER,abi.encodeCall(a.offset,(1e60-1e18,0))));
        require(!compare(MANAGER,abi.encodeCall(a.offset,(0,type(uint256).max))));
        aa.failures(false,false,true);ab.failures(false,false,true);sameView(abi.encodeCall(a.getDepositorYieldGainWithPending,(ALICE)));
    }
    function testFuzzDepositOffsetAndRewards(uint128 first,uint128 second,uint128 debt,uint64 collateral,uint64 reward,bool claim) public {
        uint x=uint(first)+1e18;uint y=uint(second)+1e18;
        ba.mint(ALICE,x);bb.mint(ALICE,x);ba.mint(BOB,y);bb.mint(BOB,y);
        require(compare(ALICE,abi.encodeCall(a.provideToSP,(x,false))));require(compare(BOB,abi.encodeCall(a.provideToSP,(y,false))));
        pending(reward);mintInterest();uint loss=uint(debt)%(x+y-1e18+1);
        require(compare(MANAGER,abi.encodeCall(a.offset,(loss,uint(collateral)))));
        require(compare(ALICE,abi.encodeCall(a.withdrawFromSP,(0,claim))));require(compare(BOB,abi.encodeCall(a.withdrawFromSP,(0,!claim))));
    }
    function testFuzzStatefulDepositorSequence(uint256 seed) public {
        require(compare(ALICE,abi.encodeCall(a.provideToSP,(1e21,false))));require(compare(BOB,abi.encodeCall(a.provideToSP,(1e21,false))));
        address[3] memory users=[ALICE,BOB,CAROL];
        for(uint i;i<16;i++) {
            seed=uint256(keccak256(abi.encode(seed,i)));address user=users[(seed>>8)%3];uint amount=(seed>>16)%1e22;bool claim=(seed&256)!=0;uint action=seed%6;
            if(action==0)compare(user,abi.encodeCall(a.provideToSP,(amount,claim)));
            else if(action==1)compare(user,abi.encodeCall(a.withdrawFromSP,(amount,claim)));
            else if(action==2) {
                uint total=a.getTotalBoldDeposits();uint available=total>1e18?total-1e18:0;
                compare(MANAGER,abi.encodeCall(a.offset,(available==0?0:amount%(available+1),(seed>>96)%1e18)));
            } else if(action==3) {pending(amount%1e18);mintInterest();}
            else if(action==4)compare(user,abi.encodeCall(a.claimAllCollGains,()));
            else {pending(amount%1e18);compare(user,abi.encodeCall(a.withdrawFromSP,(0,claim)));}
        }
    }

    function writeBoth(bytes32 slot,uint value) internal {sv.store(address(a),slot,bytes32(value));sv.store(address(b),slot,bytes32(value));}
    function testFuzzRewardGetterArithmetic(uint256 initial,uint256 product,uint256 snapshotProduct,uint256 rewardSum,uint64 scaleDiff,uint256 cap) public {
        uint scale=uint(scaleDiff)%11;writeBoth(bytes32(uint(3)),cap);writeBoth(bytes32(uint(4)),1e20);writeBoth(bytes32(uint(5)),cap);writeBoth(bytes32(uint(10)),product);writeBoth(bytes32(uint(11)),scale);
        writeBoth(keccak256(abi.encode(ALICE,uint(7))),initial);bytes32 snapshot=keccak256(abi.encode(ALICE,uint(8)));writeBoth(bytes32(uint(snapshot)+1),snapshotProduct);
        for(uint root=12;root<=13;root++)for(uint i;i<3;i++)writeBoth(keccak256(abi.encode(i,root)),rewardSum>>i);
        pending(1e18);
        sameView(abi.encodeCall(a.getDepositorCollGain,(ALICE)));sameView(abi.encodeCall(a.getDepositorYieldGain,(ALICE)));sameView(abi.encodeCall(a.getDepositorYieldGainWithPending,(ALICE)));sameView(abi.encodeCall(a.getCompoundedBoldDeposit,(ALICE)));
        if(scale>8||initial==0)require(a.getCompoundedBoldDeposit(ALICE)==0&&b.getCompoundedBoldDeposit(ALICE)==0);
    }
    function testMalformedStaticArguments() public {
        bytes memory data=abi.encodeCall(a.provideToSP,(1e18,true));assembly{mstore(add(data,68),2)}require(!compare(ALICE,data));
        data=abi.encodeCall(a.getDepositorCollGain,(ALICE));assembly{mstore(add(data,36),not(0))}require(!compare(ALICE,data));
        require(!compare(MANAGER,abi.encodePacked(a.offset.selector,uint256(1))));
    }

}
