// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {GasCompZapper} from "../reference/bold/contracts/src/Zappers/GasCompZapper.sol";
import {WETHZapper} from "../reference/bold/contracts/src/Zappers/WETHZapper.sol";
import {IZapper} from "../reference/bold/contracts/src/Zappers/Interfaces/IZapper.sol";
import {ILeverageZapper} from "../reference/bold/contracts/src/Zappers/Interfaces/ILeverageZapper.sol";
import {IFlashLoanProvider} from "../reference/bold/contracts/src/Zappers/Interfaces/IFlashLoanProvider.sol";
import {IFlashLoanReceiver} from "../reference/bold/contracts/src/Zappers/Interfaces/IFlashLoanReceiver.sol";
import {LeverageLSTZapper} from "../reference/bold/contracts/src/Zappers/LeverageLSTZapper.sol";
import {LeverageWETHZapper} from "../reference/bold/contracts/src/Zappers/LeverageWETHZapper.sol";
import {IExchange} from "../reference/bold/contracts/src/Zappers/Interfaces/IExchange.sol";
contract LeverageSystemMarkets is IExchange {
 BorrowerSystemCollateral public coll;BoldToken public bold;
 constructor(BorrowerSystemCollateral c,BoldToken b){coll=c;bold=b;}
 function makeFlashLoan(address token,uint amount,IFlashLoanProvider.Operation op,bytes calldata data) external {
  require(token==address(coll));uint effective=amount-1;coll.mint(msg.sender,effective);IFlashLoanReceiver z=IFlashLoanReceiver(msg.sender);
  if(op==IFlashLoanProvider.Operation.OpenTrove)z.receiveFlashLoanOnOpenLeveragedTrove(abi.decode(data,(ILeverageZapper.OpenLeveragedTroveParams)),effective);
  else if(op==IFlashLoanProvider.Operation.LeverUpTrove)z.receiveFlashLoanOnLeverUpTrove(abi.decode(data,(ILeverageZapper.LeverUpTroveParams)),effective);
  else if(op==IFlashLoanProvider.Operation.LeverDownTrove)z.receiveFlashLoanOnLeverDownTrove(abi.decode(data,(ILeverageZapper.LeverDownTroveParams)),effective);
  else revert("unexpected op");
 }
 function swapFromBold(uint amount,uint minimum) external{bold.transferFrom(msg.sender,address(this),amount);coll.mint(msg.sender,minimum+17);}
 function swapToBold(uint amount,uint minimum) external returns(uint){coll.transferFrom(msg.sender,address(this),amount);bold.transfer(msg.sender,minimum);return minimum;}
 function sendBold(address receiver,uint amount) external {bold.transfer(receiver,amount);}
}
import {CurveExchange} from "../reference/bold/contracts/src/Zappers/Modules/Exchanges/CurveExchange.sol";
import {UniV3Exchange} from "../reference/bold/contracts/src/Zappers/Modules/Exchanges/UniV3Exchange.sol";
import {ISwapRouter} from "../reference/bold/contracts/src/Zappers/Modules/Exchanges/UniswapV3/ISwapRouter.sol";
import {IERC20,SafeERC20} from "../reference/bold/contracts/lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
contract ExchangeSystemMarket {
 using SafeERC20 for IERC20;
 BorrowerSystemCollateral public coll;IERC20 public bold;
 constructor(BorrowerSystemCollateral c,IERC20 b){coll=c;bold=b;}
 function exchange(uint i,uint j,uint amount,uint minimum) external returns(uint){
  require(i<2&&j==1-i);bool fromBold=i==1;
  uint output=fromBold?amount/2000:amount*2000;require(output>=minimum,"minimum");
  if(fromBold){bold.safeTransferFrom(msg.sender,address(this),amount);coll.mint(msg.sender,output);}
  else{coll.transferFrom(msg.sender,address(this),amount);bold.safeTransfer(msg.sender,output);}
  return output;
 }
 function exactOutputSingle(ISwapRouter.ExactOutputSingleParams calldata p) external returns(uint){
  require(p.tokenIn==address(bold)&&p.tokenOut==address(coll)&&p.fee==3000&&p.deadline==block.timestamp&&p.sqrtPriceLimitX96==0,"parameters");
  uint input=p.amountOut*2000;require(input<=p.amountInMaximum);bold.safeTransferFrom(msg.sender,address(this),input);coll.mint(p.recipient,p.amountOut);return input;
 }
 function exactInputSingle(ISwapRouter.ExactInputSingleParams calldata p) external returns(uint){
  require(p.tokenIn==address(coll)&&p.tokenOut==address(bold)&&p.fee==3000&&p.deadline==block.timestamp&&p.sqrtPriceLimitX96==0,"parameters");
  uint output=p.amountIn*2000;require(output>=p.amountOutMinimum);coll.transferFrom(msg.sender,address(this),p.amountIn);bold.safeTransfer(p.recipient,output);return output;
 }
 function returnBold(address receiver) external {bold.safeTransfer(receiver,bold.balanceOf(address(this)));}
}
interface ZapperSystemVm {function deal(address,uint) external;}
import {RedemptionHelper} from "../reference/bold/contracts/src/RedemptionHelper.sol";
import {CollateralRegistry} from "../reference/bold/contracts/src/CollateralRegistry.sol";
import {DebtInFrontHelper} from "../reference/bold/contracts/src/DebtInFrontHelper.sol";
import {HintHelpers} from "../reference/bold/contracts/src/HintHelpers.sol";
import {MultiTroveGetter} from "../reference/bold/contracts/src/MultiTroveGetter.sol";
import {IMultiTroveGetter} from "../reference/bold/contracts/src/Interfaces/IMultiTroveGetter.sol";
import {WETHPriceFeed} from "../reference/bold/contracts/src/PriceFeeds/WETHPriceFeed.sol";
import {FeedOracle} from "./PriceFeedParity.t.sol";
import {BorrowerOperations} from "../reference/bold/contracts/src/BorrowerOperations.sol";
import {AddressesRegistry} from "../reference/bold/contracts/src/AddressesRegistry.sol";
import {ActivePool} from "../reference/bold/contracts/src/ActivePool.sol";
import {DefaultPool} from "../reference/bold/contracts/src/DefaultPool.sol";
import {StabilityPool} from "../reference/bold/contracts/src/StabilityPool.sol";
import {CollSurplusPool} from "../reference/bold/contracts/src/CollSurplusPool.sol";
import {GasPool} from "../reference/bold/contracts/src/GasPool.sol";
import {BoldToken} from "../reference/bold/contracts/src/BoldToken.sol";
import {TroveManager,LatestTroveData} from "../reference/bold/contracts/src/TroveManager.sol";
import {TroveNFT} from "../reference/bold/contracts/src/TroveNFT.sol";
import {SortedTroves} from "../reference/bold/contracts/src/SortedTroves.sol";
import {TroveChange} from "../reference/bold/contracts/src/Types/TroveChange.sol";
import {ActiveCollateralToken,TimeVm} from "./ActivePoolParity.t.sol";
import {PoolVm} from "./DefaultPoolParity.t.sol";
interface BOSystemVm {function envOr(string calldata,string calldata) external returns(string memory);}
contract BorrowerSystemCollateral is ActiveCollateralToken {
    function deposit() external payable {balanceOf[msg.sender]+=msg.value;}
    function withdraw(uint amount) external {balanceOf[msg.sender]-=amount;(bool ok,)=msg.sender.call{value:amount}("");require(ok);}

    function name() external pure returns(string memory){return "Collateral";}
    function symbol() external pure returns(string memory){return "COLL";}
}
contract BorrowerSystemPrice {
    uint public price=2000e18;
    function set(uint value) external {price=value;}
    function fetchPrice() external view returns(uint,bool){return(price,false);}
    function fetchRedemptionPrice() external view returns(uint,bool){return(price,false);}
}
contract BorrowerOperationsSystemTest {
    PoolVm constant vm=PoolVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address constant ALICE=address(0xa11ce);address constant BOB=address(0xb0b);address constant ROUTER=address(0x100);
    struct System {
        CollateralRegistry cr;AddressesRegistry registry;ActivePool active;DefaultPool defaults;StabilityPool sp;BoldToken bold;BorrowerSystemCollateral coll;BorrowerSystemCollateral weth;
        WETHPriceFeed oracleFeed;FeedOracle oracle;BorrowerOperations bo;TroveManager manager;TroveNFT nft;SortedTroves sorted;CollSurplusPool surplus;address gasPool;BorrowerSystemPrice feed;
    }
    function code(string memory name,bool fe) internal returns(bytes memory){
        if(fe&&(keccak256(bytes(name))==keccak256("BorrowerOperations")||keccak256(bytes(name))==keccak256("BorrowerOpening")||keccak256(bytes(name))==keccak256("BorrowerAdjustments")||keccak256(bytes(name))==keccak256("BorrowerBatches")))return vm.parseBytes(vm.readFile(string.concat(BOSystemVm(address(vm)).envOr("LIQUITY_BORROWER_ARTIFACTS","build"),"/",name,".bin")));
        if(fe)return vm.parseBytes(vm.readFile(string.concat(BOSystemVm(address(vm)).envOr("LIQUITY_TEST_ARTIFACTS","build"),"/",name,".bin")));
        bytes32 k=keccak256(bytes(name));
        if(k==keccak256("GasCompZapper"))return type(GasCompZapper).creationCode;
        if(k==keccak256("WETHZapper"))return type(WETHZapper).creationCode;
        if(k==keccak256("RedemptionHelper"))return type(RedemptionHelper).creationCode;
        if(k==keccak256("CollateralRegistry"))return type(CollateralRegistry).creationCode;
        if(k==keccak256("DebtInFrontHelper"))return type(DebtInFrontHelper).creationCode;
        if(k==keccak256("HintHelpers"))return type(HintHelpers).creationCode;
        if(k==keccak256("MultiTroveGetter"))return type(MultiTroveGetter).creationCode;
        if(k==keccak256("WETHPriceFeed"))return type(WETHPriceFeed).creationCode;
        if(k==keccak256("BorrowerOperations"))return type(BorrowerOperations).creationCode;
        if(k==keccak256("AddressesRegistry"))return type(AddressesRegistry).creationCode;
        if(k==keccak256("ActivePool"))return type(ActivePool).creationCode;
        if(k==keccak256("DefaultPool"))return type(DefaultPool).creationCode;
        if(k==keccak256("StabilityPool"))return type(StabilityPool).creationCode;
        if(k==keccak256("BoldToken"))return type(BoldToken).creationCode;
        if(k==keccak256("TroveManager"))return type(TroveManager).creationCode;
        if(k==keccak256("TroveNFT"))return type(TroveNFT).creationCode;
        if(k==keccak256("SortedTroves"))return type(SortedTroves).creationCode;
        if(k==keccak256("CollSurplusPool"))return type(CollSurplusPool).creationCode;
        if(k==keccak256("GasPool"))return type(GasPool).creationCode;
        revert("unknown contract");
    }
    function predict(bytes memory init) internal view returns(address){return address(uint160(uint256(keccak256(abi.encodePacked(hex"ff",address(this),bytes32(0),keccak256(init))))));}
    function deploy(bytes memory init) internal returns(address target){require(init.length<=49152,"initcode");assembly{target:=create2(0,add(init,32),mload(init),0)}require(target.code.length>0&&target.code.length<=24576,"deploy");}
    function make(bool fe) internal returns(System memory s){return makeWithOracle(fe,false);}
    function makeWithOracle(bool fe,bool realOracle) internal returns(System memory){return makeWithRegistry(fe,realOracle,false);}
    function makeWithRegistry(bool fe,bool realOracle,bool realRegistry) internal returns(System memory){return makeWithWeth(fe,realOracle,realRegistry,false);}
    function makeWithWeth(bool fe,bool realOracle,bool realRegistry,bool separateWeth) internal returns(System memory s){
        s.coll=new BorrowerSystemCollateral();s.weth=separateWeth?new BorrowerSystemCollateral():s.coll;s.feed=new BorrowerSystemPrice();
        s.registry=AddressesRegistry(deploy(bytes.concat(code("AddressesRegistry",fe),abi.encode(address(this),15e17,11e17,1e17,11e17,5e16,1e17))));
        s.bold=BoldToken(deploy(bytes.concat(code("BoldToken",fe),abi.encode(address(this)))));
        bytes[10] memory init;
        bytes[3] memory borrowerModules;
        if(fe){
            borrowerModules[0]=bytes.concat(code("BorrowerOpening",true),abi.encode(s.registry));
            borrowerModules[1]=bytes.concat(code("BorrowerAdjustments",true),abi.encode(s.registry));
            borrowerModules[2]=bytes.concat(code("BorrowerBatches",true),abi.encode(s.registry));
            init[8]=bytes.concat(code("BorrowerOperations",true),abi.encode(s.registry,predict(borrowerModules[0]),predict(borrowerModules[1]),predict(borrowerModules[2])));
        }else init[8]=bytes.concat(code("BorrowerOperations",false),abi.encode(s.registry));
        init[0]=bytes.concat(code("ActivePool",fe),abi.encode(s.registry));init[1]=bytes.concat(code("DefaultPool",fe),abi.encode(s.registry));init[2]=bytes.concat(code("StabilityPool",fe),abi.encode(s.registry));
        bytes[3] memory modules;
        if(fe){modules[0]=code("TroveOperations",true);modules[1]=code("TroveRedemptions",true);modules[2]=bytes.concat(code("TroveLiquidations",true),abi.encode(s.registry));
            init[3]=bytes.concat(code("TroveManager",true),abi.encode(s.registry,predict(modules[0]),predict(modules[1]),predict(modules[2])));
        }else init[3]=bytes.concat(code("TroveManager",false),abi.encode(s.registry));
        init[4]=bytes.concat(code("TroveNFT",fe),abi.encode(s.registry));init[5]=bytes.concat(code("SortedTroves",fe),abi.encode(s.registry));init[6]=bytes.concat(code("GasPool",fe),abi.encode(s.registry));init[7]=bytes.concat(code("CollSurplusPool",fe),abi.encode(s.registry));
        if(realOracle){
            s.oracle=new FeedOracle(8,2000e8);
            init[9]=bytes.concat(code("WETHPriceFeed",fe),abi.encode(s.oracle,3600,predict(init[8])));
        }
        if(realRegistry){address[] memory tokens=new address[](1);tokens[0]=address(s.coll);address[] memory managers=new address[](1);managers[0]=predict(init[3]);s.cr=CollateralRegistry(deploy(bytes.concat(code("CollateralRegistry",fe),abi.encode(s.bold,tokens,managers))));}
        address[18] memory vars;vars[0]=address(s.coll);vars[1]=predict(init[8]);vars[2]=predict(init[3]);vars[3]=predict(init[4]);vars[5]=predict(init[2]);vars[6]=realOracle?predict(init[9]):address(s.feed);vars[7]=predict(init[0]);vars[8]=predict(init[1]);vars[9]=predict(init[6]);vars[10]=predict(init[7]);vars[11]=predict(init[5]);vars[12]=ROUTER;vars[15]=realRegistry?address(s.cr):address(this);vars[16]=address(s.bold);vars[17]=address(s.weth);
        (bool ok,)=address(s.registry).call(abi.encodePacked(AddressesRegistry.setAddresses.selector,abi.encode(vars)));require(ok);
        if(fe){deploy(modules[0]);deploy(modules[1]);deploy(modules[2]);deploy(borrowerModules[0]);deploy(borrowerModules[1]);deploy(borrowerModules[2]);}
        s.active=ActivePool(deploy(init[0]));s.defaults=DefaultPool(deploy(init[1]));s.sp=StabilityPool(deploy(init[2]));s.manager=TroveManager(deploy(init[3]));s.nft=TroveNFT(deploy(init[4]));s.sorted=SortedTroves(deploy(init[5]));s.gasPool=deploy(init[6]);s.surplus=CollSurplusPool(deploy(init[7]));
        s.bo=BorrowerOperations(deploy(init[8]));
        if(realOracle)s.oracleFeed=WETHPriceFeed(deploy(init[9]));
        s.bold.setBranchAddresses(address(s.manager),address(s.sp),address(s.bo),address(s.active));s.bold.setCollateralRegistry(realRegistry?address(s.cr):address(this));
    }
    function id(address owner,uint index) internal pure returns(uint){return uint(keccak256(abi.encode(owner,owner,index)));}
    function open(System memory s,uint index,address owner,uint coll,uint rate) internal {
        s.coll.mint(owner,coll+375e14);
        if(address(s.weth)!=address(s.coll)){s.weth.mint(owner,375e14);vm.prank(owner);s.weth.approve(address(s.bo),type(uint).max);}
        vm.prank(owner);s.coll.approve(address(s.bo),type(uint).max);
        vm.prank(owner);uint opened=s.bo.openTrove(owner,index,coll,3000e18,0,0,rate,type(uint).max,address(0),address(0),address(0));
        require(opened==id(owner,index),"trove ID");
    }
    function conserve(System memory s) internal view {
        require(s.bold.balanceOf(address(s.sp))==s.sp.getTotalBoldDeposits()+s.sp.getYieldGainsOwed()+s.sp.getYieldGainsPending(),"BOLD conservation");
        require(s.coll.balanceOf(address(s.active))==s.active.getCollBalance(),"active collateral");
        require(s.coll.balanceOf(address(s.defaults))==s.defaults.getCollBalance(),"default collateral");
        require(s.coll.balanceOf(address(s.sp))==s.sp.getCollBalance(),"SP collateral");
    }
    function run(System memory s) internal returns(bytes32){
        open(s,1,ALICE,20e18,5e16);open(s,2,BOB,10e18,6e16);open(s,3,ALICE,30e18,7e16);
        s.coll.mint(ALICE,1e18);vm.prank(ALICE);s.bo.addColl(id(ALICE,1),1e18);
        vm.prank(ALICE);s.bo.withdrawBold(id(ALICE,1),100e18,type(uint).max);
        vm.prank(ALICE);s.bo.repayBold(id(ALICE,1),50e18);
        vm.prank(ALICE);s.bo.adjustTroveInterestRate(id(ALICE,1),8e16,0,0,type(uint).max);
        s.bo.registerBatchManager(5e15,25e17,7e16,1e16,3600);
        vm.prank(ALICE);s.bo.setInterestBatchManager(id(ALICE,3),address(this),0,0,type(uint).max);
        conserve(s);
        vm.prank(ALICE);s.sp.provideToSP(1500e18,false);TimeVm(address(vm)).warp(block.timestamp+365 days);
        s.feed.set(300e18);uint[] memory ids=new uint[](1);ids[0]=id(BOB,2);s.manager.batchLiquidateTroves(ids);
        require(uint(s.manager.getTroveStatus(id(BOB,2)))==3&&!s.sorted.contains(id(BOB,2))&&s.nft.balanceOf(BOB)==0);conserve(s);
        uint redeemed=s.manager.redeemCollateral(ALICE,1000e18,300e18,5e15,0);s.bold.burn(ALICE,redeemed);require(redeemed==1000e18);conserve(s);
        s.feed.set(100e18);s.bo.shutdown();require(s.bo.hasBeenShutDown());ids=new uint[](2);ids[0]=id(ALICE,3);ids[1]=id(ALICE,1);vm.prank(ALICE);s.manager.urgentRedemption(2000e18,ids,0);conserve(s);
        vm.prank(ALICE);s.sp.withdrawFromSP(0,true);conserve(s);
        LatestTroveData memory one=s.manager.getLatestTroveData(id(ALICE,1));LatestTroveData memory three=s.manager.getLatestTroveData(id(ALICE,3));
        bytes32 pools=keccak256(abi.encode(s.active.getCollBalance(),s.active.getBoldDebt(),s.defaults.getCollBalance(),s.defaults.getBoldDebt(),s.sp.getTotalBoldDeposits(),s.sp.getCollBalance(),s.sp.getYieldGainsOwed(),s.sp.getYieldGainsPending()));
        bytes32 balances=keccak256(abi.encode(s.bold.totalSupply(),s.bold.balanceOf(ALICE),s.bold.balanceOf(BOB),s.bold.balanceOf(ROUTER),s.coll.balanceOf(ALICE),s.coll.balanceOf(address(this)),s.coll.balanceOf(s.gasPool)));
        return keccak256(abi.encode(one,three,pools,balances,s.sorted.getSize(),s.manager.getTroveIdsCount(),s.bold.balanceOf(address(this))));
    }
    function runClose(System memory s) internal returns(bytes32){
        open(s,1,ALICE,20e18,5e16);open(s,2,BOB,10e18,6e16);open(s,3,ALICE,30e18,7e16);
        s.bo.registerBatchManager(5e15,25e17,7e16,1e16,3600);
        vm.prank(ALICE);s.bo.setInterestBatchManager(id(ALICE,3),address(this),0,0,type(uint).max);
        TimeVm(address(vm)).warp(block.timestamp+1 days);
        s.bo.applyPendingDebt(id(ALICE,3),0,0);
        vm.prank(BOB);s.bold.transfer(ALICE,200e18);
        vm.prank(ALICE);s.bo.closeTrove(id(ALICE,1));conserve(s);
        vm.prank(ALICE);s.bo.closeTrove(id(ALICE,3));conserve(s);
        require(s.nft.balanceOf(ALICE)==0&&s.sorted.getSize()==1&&s.bo.interestBatchManagerOf(id(ALICE,3))==address(0));
        return keccak256(abi.encode(s.active.getCollBalance(),s.active.getBoldDebt(),s.bold.totalSupply(),s.bold.balanceOf(ALICE),s.coll.balanceOf(ALICE),s.coll.balanceOf(s.gasPool),s.manager.getLatestBatchData(address(this))));
    }
    function testActualIndividualAndBatchClosing() public {
        TimeVm(address(vm)).warp(1000);bytes32 actual=runClose(make(true));
        TimeVm(address(vm)).warp(1000);bytes32 expected=runClose(make(false));require(actual==expected,"connected closing parity");
    }
    function runOracleShutdown(System memory s) internal returns(bytes32){
        open(s,1,ALICE,20e18,5e16);open(s,2,BOB,10e18,6e16);
        TimeVm(address(vm)).warp(1100);s.oracle.set(0,1100,0);
        (uint price,bool failed)=s.oracleFeed.fetchPrice();
        require(price==2000e18&&failed&&s.bo.hasBeenShutDown()&&s.manager.shutdownTime()==1100,"oracle shutdown");
        vm.prank(ALICE);(bool ok,bytes memory reason)=address(s.bo).call(abi.encodeCall(s.bo.addColl,(id(ALICE,1),1e18)));
        require(!ok&&keccak256(reason)==keccak256(abi.encodeWithSignature("IsShutDown()")));
        s.oracle.set(5000e8,1100,0);(price,failed)=s.oracleFeed.fetchPrice();require(price==2000e18&&!failed,"frozen fallback");
        vm.prank(BOB);s.bold.transfer(ALICE,100e18);
        vm.prank(ALICE);s.bo.closeTrove(id(ALICE,1));conserve(s);
        return keccak256(abi.encode(s.active.getCollBalance(),s.active.getBoldDebt(),s.bold.totalSupply(),s.bold.balanceOf(ALICE),s.coll.balanceOf(ALICE),s.coll.balanceOf(s.gasPool),s.manager.shutdownTime(),s.oracleFeed.lastGoodPrice(),s.oracleFeed.priceSource()));
    }
    function testActualOracleFailureShutsDownBorrowingAndManager() public {
        TimeVm(address(vm)).warp(1000);bytes32 actual=runOracleShutdown(makeWithOracle(true,true));
        TimeVm(address(vm)).warp(1000);bytes32 expected=runOracleShutdown(makeWithOracle(false,true));require(actual==expected,"connected oracle shutdown parity");
    }
    address internal helperManager;
    function getTroveManager(uint index) external view returns(address){return index==0?helperManager:address(0);}
    function helperResult(HintHelpers hints,MultiTroveGetter getter) internal view returns(bytes32){
        bytes32 page=keccak256(abi.encode(getter.getMultipleSortedTroves(0,0,10),getter.getMultipleSortedTroves(0,-1,10)));
        (uint hint,uint distance,uint seed)=hints.getApproxHint(0,7e16,20,123);
        (IMultiTroveGetter.DebtPerInterestRate[] memory data,uint cursor)=getter.getDebtPerInterestRateAscending(0,0,5);
        return keccak256(abi.encode(page,hint,distance,seed,data,cursor));
    }
    function runHelpers(System memory s,bool fe) internal returns(bytes32){
        helperManager=address(s.manager);
        HintHelpers hints=HintHelpers(deploy(bytes.concat(code("HintHelpers",fe),abi.encode(address(this)))));
        MultiTroveGetter getter=MultiTroveGetter(deploy(bytes.concat(code("MultiTroveGetter",fe),abi.encode(address(this)))));
        uint expected=hints.predictOpenTroveUpfrontFee(0,3000e18,5e16);
        open(s,1,ALICE,20e18,5e16);require(s.manager.getLatestTroveData(id(ALICE,1)).entireDebt==3000e18+expected,"open prediction");
        open(s,2,BOB,10e18,6e16);open(s,3,ALICE,30e18,7e16);
        expected=hints.predictAdjustInterestRateUpfrontFee(0,id(ALICE,1),8e16);
        uint beforeDebt=s.manager.getLatestTroveData(id(ALICE,1)).entireDebt;
        vm.prank(ALICE);s.bo.adjustTroveInterestRate(id(ALICE,1),8e16,0,0,expected);
        require(s.manager.getLatestTroveData(id(ALICE,1)).entireDebt==beforeDebt+expected,"rate prediction");
        s.bo.registerBatchManager(5e15,25e17,7e16,1e16,3600);
        expected=hints.predictJoinBatchInterestRateUpfrontFee(0,id(ALICE,3),address(this));
        beforeDebt=s.manager.getLatestTroveData(id(ALICE,3)).entireDebt;
        vm.prank(ALICE);s.bo.setInterestBatchManager(id(ALICE,3),address(this),0,0,expected);
        require(s.manager.getLatestTroveData(id(ALICE,3)).entireDebt==beforeDebt+expected,"batch prediction");
        DebtInFrontHelper debt=DebtInFrontHelper(deploy(bytes.concat(code("DebtInFrontHelper",fe),abi.encode(address(this),address(hints)))));
        (uint total,uint timestamp)=debt.getDebtBetweenInterestRates(0,0,9e16,0,0,20);
        require(total==s.manager.getLatestTroveData(id(ALICE,1)).entireDebt+s.manager.getLatestTroveData(id(BOB,2)).entireDebt+s.manager.getLatestTroveData(id(ALICE,3)).entireDebt,"debt range");
        require(timestamp==block.timestamp,"timestamp");
        (uint front,)=debt.getDebtBetweenInterestRateAndTrove(0,0,9e16,id(ALICE,3),0,20);
        require(front==s.manager.getLatestTroveData(id(BOB,2)).entireDebt,"debt in front");
        conserve(s);return keccak256(abi.encode(helperResult(hints,getter),total,front,timestamp));
    }
    function testActualFeePredictionsAndSortedGetter() public {
        TimeVm(address(vm)).warp(1000);bytes32 actual=runHelpers(make(true),true);
        TimeVm(address(vm)).warp(1000);bytes32 expected=runHelpers(make(false),false);require(actual==expected,"connected helper parity");
    }
    function testActualBorrowingLiquidationRedemptionAndShutdown() public {
        TimeVm(address(vm)).warp(1000);bytes32 actual=run(make(true));
        TimeVm(address(vm)).warp(1000);bytes32 expected=run(make(false));require(actual==expected,"connected borrower parity");
    }
    function runRedemptionHelper(bool fe) internal returns(bytes32){
        System memory s=makeWithRegistry(fe,false,true);
        open(s,1,ALICE,20e18,5e16);open(s,2,BOB,10e18,6e16);open(s,3,ALICE,30e18,7e16);
        address[] memory registries=new address[](1);registries[0]=address(s.registry);
        RedemptionHelper helper=RedemptionHelper(deploy(bytes.concat(code("RedemptionHelper",fe),abi.encode(s.cr,registries))));
        TimeVm(address(vm)).warp(block.timestamp+14 days);
        (uint truncated,uint fee,RedemptionHelper.Redeemed[] memory projected)=helper.truncateRedemption(4000e18,1);
        require(truncated>3000e18&&truncated<4000e18,"iteration truncation");require(projected.length==1&&projected[0].bold==truncated,"projection");
        uint[] memory minimum=new uint[](1);minimum[0]=projected[0].coll;
        vm.prank(ALICE);s.bold.approve(address(helper),type(uint).max);
        uint before=s.coll.balanceOf(ALICE);uint beforeBold=s.bold.balanceOf(ALICE);
        vm.prank(ALICE);helper.redeemCollateral(truncated,1,fee,minimum);
        require(s.coll.balanceOf(ALICE)-before>=minimum[0],"redemption collateral");
        require(beforeBold-s.bold.balanceOf(ALICE)==truncated,"redeemed BOLD");
        require(s.bold.balanceOf(address(helper))==0&&s.coll.balanceOf(address(helper))==0,"helper residual");
        conserve(s);
        return keccak256(abi.encode(truncated,fee,minimum,s.coll.balanceOf(ALICE)-before,s.bold.totalSupply(),s.active.getBoldDebt(),s.active.getCollBalance(),s.manager.lastZombieTroveId()));
    }
    function testActualRedemptionHelperAndCollateralRegistry() public {
        TimeVm(address(vm)).warp(1000);bytes32 actual=runRedemptionHelper(true);
        TimeVm(address(vm)).warp(1000);bytes32 expected=runRedemptionHelper(false);
        require(actual==expected,"connected redemption helper parity");
    }
    function runWETHZapper(bool fe) internal returns(bytes32){
        System memory s=make(fe);open(s,2,BOB,10e18,6e16);
        WETHZapper zapper=WETHZapper(payable(deploy(bytes.concat(code("WETHZapper",fe),abi.encode(s.registry,address(77),address(88))))));
        ZapperSystemVm(address(vm)).deal(ALICE,100e18);
        IZapper.OpenTroveParams memory p=IZapper.OpenTroveParams(ALICE,1,999,3000e18,0,0,5e16,address(0),type(uint).max,address(0),address(0),address(0));
        vm.prank(ALICE);uint trove=zapper.openTroveWithRawETH{value:20e18+375e14}(p);
        uint ownerIndex=uint(keccak256(abi.encode(ALICE,uint(1))));require(trove==uint(keccak256(abi.encode(address(zapper),ALICE,ownerIndex))),"zapper trove ID");
        vm.prank(ALICE);s.bold.approve(address(zapper),type(uint).max);
        vm.prank(ALICE);zapper.addCollWithRawETH{value:2e18}(trove);
        vm.prank(ALICE);zapper.withdrawCollToRawETH(trove,1e18);
        vm.prank(ALICE);zapper.withdrawBold(trove,100e18,type(uint).max);
        vm.prank(ALICE);zapper.repayBold(trove,50e18);
        vm.prank(ALICE);zapper.adjustTroveWithRawETH(trove,5e17,false,100e18,true,type(uint).max);
        require(s.manager.getLatestTroveData(trove).entireColl==205e17,"zapper collateral");
        vm.prank(BOB);s.bold.transfer(ALICE,100e18);
        vm.prank(ALICE);zapper.closeTroveToRawETH(trove);
        require(s.bold.balanceOf(address(zapper))==0&&s.coll.balanceOf(address(zapper))==0&&address(zapper).balance==0,"zapper residual");
        conserve(s);
        return keccak256(abi.encode(ALICE.balance,s.bold.balanceOf(ALICE),s.bold.totalSupply(),s.active.getBoldDebt(),s.active.getCollBalance(),s.sorted.getSize()));
    }
    function testActualWETHZapperLifecycle() public {
        TimeVm(address(vm)).warp(1000);bytes32 actual=runWETHZapper(true);
        TimeVm(address(vm)).warp(1000);bytes32 expected=runWETHZapper(false);
        require(actual==expected,"connected WETH zapper parity");
    }
    function runGasCompZapper(bool fe) internal returns(bytes32){
        System memory s=makeWithWeth(fe,false,false,true);open(s,2,BOB,10e18,6e16);
        GasCompZapper zapper=GasCompZapper(payable(deploy(bytes.concat(code("GasCompZapper",fe),abi.encode(s.registry,address(77),address(88))))));
        ZapperSystemVm(address(vm)).deal(ALICE,100e18);
        IZapper.OpenTroveParams memory p=IZapper.OpenTroveParams(ALICE,1,20e18,3000e18,0,0,5e16,address(0),type(uint).max,address(0),address(0),address(0));
        s.coll.mint(ALICE,22e18);vm.prank(ALICE);s.coll.approve(address(zapper),type(uint).max);
        vm.prank(ALICE);uint trove=zapper.openTroveWithRawETH{value:375e14}(p);
        uint ownerIndex=uint(keccak256(abi.encode(ALICE,uint(1))));require(trove==uint(keccak256(abi.encode(address(zapper),ALICE,ownerIndex))),"zapper trove ID");
        vm.prank(ALICE);s.bold.approve(address(zapper),type(uint).max);
        vm.prank(ALICE);zapper.addColl(trove,2e18);
        vm.prank(ALICE);zapper.withdrawColl(trove,1e18);
        vm.prank(ALICE);zapper.withdrawBold(trove,100e18,type(uint).max);
        vm.prank(ALICE);zapper.repayBold(trove,50e18);
        vm.prank(ALICE);zapper.adjustTrove(trove,5e17,false,100e18,true,type(uint).max);
        require(s.manager.getLatestTroveData(trove).entireColl==205e17,"zapper collateral");
        vm.prank(BOB);s.bold.transfer(ALICE,100e18);
        vm.prank(ALICE);zapper.closeTroveToRawETH(trove);
        require(s.bold.balanceOf(address(zapper))==0&&s.coll.balanceOf(address(zapper))==0&&address(zapper).balance==0,"zapper residual");
        conserve(s);
        return keccak256(abi.encode(ALICE.balance,s.coll.balanceOf(ALICE),s.bold.balanceOf(ALICE),s.bold.totalSupply(),s.active.getBoldDebt(),s.active.getCollBalance(),s.sorted.getSize()));
    }
    function testActualGasCompZapperLifecycle() public {
        TimeVm(address(vm)).warp(1000);bytes32 actual=runGasCompZapper(true);
        TimeVm(address(vm)).warp(1000);bytes32 expected=runGasCompZapper(false);
        require(actual==expected,"connected gas compensation zapper parity");
    }
 function runLeverage(bool fe,bool lst) internal returns(bytes32){
  System memory s=makeWithWeth(fe,false,false,lst);open(s,2,BOB,10e18,6e16);
  LeverageSystemMarkets markets=new LeverageSystemMarkets(s.coll,s.bold);
  bytes memory zapperCode=fe?code(lst?"LeverageLSTZapper":"LeverageWETHZapper",true):(lst?type(LeverageLSTZapper).creationCode:type(LeverageWETHZapper).creationCode);
  ILeverageZapper z=ILeverageZapper(deploy(bytes.concat(zapperCode,abi.encode(s.registry,markets,markets))));
  ZapperSystemVm(address(vm)).deal(ALICE,100e18);ZapperSystemVm(address(vm)).deal(address(s.weth),1000e18);
  if(lst){s.coll.mint(ALICE,20e18);vm.prank(ALICE);s.coll.approve(address(z),type(uint).max);}
  ILeverageZapper.OpenLeveragedTroveParams memory p=ILeverageZapper.OpenLeveragedTroveParams(ALICE,1,20e18,5e18,3000e18,0,0,5e16,address(0),type(uint).max,address(0),address(0),address(0));
  vm.prank(ALICE);z.openLeveragedTroveWithRawETH{value:375e14+(lst?0:20e18)}(p);
  uint id=uint(keccak256(abi.encode(address(z),ALICE,uint(keccak256(abi.encode(ALICE,uint(1)))))));
  require(s.nft.ownerOf(id)==ALICE&&s.manager.getLatestTroveData(id).entireColl==25e18-1,"leveraged opening");
  vm.prank(ALICE);z.leverUpTrove(ILeverageZapper.LeverUpTroveParams(id,2e18,500e18,type(uint).max));
  vm.prank(ALICE);z.leverDownTrove(ILeverageZapper.LeverDownTroveParams(id,1e18,300e18));
  require(s.manager.getLatestTroveData(id).entireColl==26e18-2,"leverage adjustment");conserve(s);
  markets.sendBold(ALICE,3200e18);vm.prank(BOB);s.bold.transfer(ALICE,100e18);
  vm.prank(ALICE);s.bold.approve(address(z),type(uint).max);
  vm.prank(ALICE);WETHZapper(payable(address(z))).closeTroveToRawETH(id);
  require(s.bold.balanceOf(address(z))==0&&s.coll.balanceOf(address(z))==0&&address(z).balance==0,"leverage residual");conserve(s);
  return keccak256(abi.encode(ALICE.balance,s.coll.balanceOf(ALICE),s.bold.balanceOf(ALICE),s.bold.totalSupply(),s.active.getBoldDebt(),s.active.getCollBalance(),s.sorted.getSize()));
 }
 function compareLeverage(bool lst) internal {
  TimeVm(address(vm)).warp(1000);bytes32 actual=runLeverage(true,lst);
  TimeVm(address(vm)).warp(1000);bytes32 expected=runLeverage(false,lst);
  require(actual==expected,"connected leverage parity");
 }
 function testActualLeverageWETH() public {compareLeverage(false);}
 function testActualLeverageLST() public {compareLeverage(true);}
 function runActualExchange(bool fe,bool lst,bool uni) internal returns(bytes32){
  System memory s=makeWithWeth(fe,false,false,lst);open(s,2,BOB,10e18,6e16);
  LeverageSystemMarkets flash=new LeverageSystemMarkets(s.coll,s.bold);ExchangeSystemMarket market=new ExchangeSystemMarket(s.coll,IERC20(address(s.bold)));
  bytes memory exchangeCode=fe?code(uni?"UniV3Exchange":"CurveExchange",true):(uni?type(UniV3Exchange).creationCode:type(CurveExchange).creationCode);
  address exchange=deploy(bytes.concat(exchangeCode,uni?abi.encode(s.coll,s.bold,uint24(3000),market):abi.encode(s.coll,s.bold,market,uint(0),uint(1))));
  bytes memory zapperCode=fe?code(lst?"LeverageLSTZapper":"LeverageWETHZapper",true):(lst?type(LeverageLSTZapper).creationCode:type(LeverageWETHZapper).creationCode);
  ILeverageZapper z=ILeverageZapper(deploy(bytes.concat(zapperCode,abi.encode(s.registry,flash,exchange))));
  ZapperSystemVm(address(vm)).deal(ALICE,100e18);ZapperSystemVm(address(vm)).deal(address(s.weth),1000e18);
  if(lst){s.coll.mint(ALICE,20e18);vm.prank(ALICE);s.coll.approve(address(z),type(uint).max);}
  ILeverageZapper.OpenLeveragedTroveParams memory p=ILeverageZapper.OpenLeveragedTroveParams(ALICE,1,20e18,1e18,3000e18,0,0,5e16,address(0),type(uint).max,address(0),address(0),address(0));
  vm.prank(ALICE);z.openLeveragedTroveWithRawETH{value:375e14+(lst?0:20e18)}(p);
  uint trove=uint(keccak256(abi.encode(address(z),ALICE,uint(keccak256(abi.encode(ALICE,uint(1)))))));
  require(s.manager.getLatestTroveData(trove).entireColl==21e18-1,"open collateral");
  vm.prank(ALICE);z.leverUpTrove(ILeverageZapper.LeverUpTroveParams(trove,1e17,500e18,type(uint).max));
  vm.prank(ALICE);z.leverDownTrove(ILeverageZapper.LeverDownTroveParams(trove,1e17,199e18));
  require(s.manager.getLatestTroveData(trove).entireColl==21e18-2,"adjust collateral");conserve(s);
  market.returnBold(ALICE);vm.prank(BOB);s.bold.transfer(ALICE,100e18);
  vm.prank(ALICE);s.bold.approve(address(z),type(uint).max);vm.prank(ALICE);WETHZapper(payable(address(z))).closeTroveToRawETH(trove);conserve(s);
  require(s.bold.balanceOf(address(z))==0&&s.coll.balanceOf(address(z))==0&&s.bold.balanceOf(exchange)==0&&s.coll.balanceOf(exchange)==0,"residual balances");
  return keccak256(abi.encode(ALICE.balance,s.coll.balanceOf(ALICE),s.bold.balanceOf(ALICE),s.bold.totalSupply(),s.active.getBoldDebt(),s.active.getCollBalance(),s.sorted.getSize()));
 }
 function compareActualExchange(bool lst,bool uni) internal {
  TimeVm(address(vm)).warp(1000);bytes32 actual=runActualExchange(true,lst,uni);
  TimeVm(address(vm)).warp(1000);bytes32 expected=runActualExchange(false,lst,uni);require(actual==expected,"connected exchange parity");
 }
 function testActualCurveWETH() public {compareActualExchange(false,false);}
 function testActualCurveLST() public {compareActualExchange(true,false);}
 function testActualUniWETH() public {compareActualExchange(false,true);}
 function testActualUniLST() public {compareActualExchange(true,true);}
}
