// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {GasCompZapper,IAddressesRegistry,IFlashLoanProvider,IExchange,IBorrowerOperations,LatestTroveData} from "../reference/bold/contracts/src/Zappers/GasCompZapper.sol";
import {IZapper} from "../reference/bold/contracts/src/Zappers/Interfaces/IZapper.sol";
import {IERC20,SafeERC20} from "../reference/bold/contracts/lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
interface LZVm {function readFile(string calldata) external view returns(string memory);function parseBytes(string calldata) external pure returns(bytes memory);function deal(address,uint) external;}
import {LeverageWETHZapper} from "../reference/bold/contracts/src/Zappers/LeverageWETHZapper.sol";
import {LeverageLSTZapper} from "../reference/bold/contracts/src/Zappers/LeverageLSTZapper.sol";
import {ILeverageZapper} from "../reference/bold/contracts/src/Zappers/Interfaces/ILeverageZapper.sol";
import {IFlashLoanReceiver} from "../reference/bold/contracts/src/Zappers/Interfaces/IFlashLoanReceiver.sol";
contract LZToken {
 uint public mode;function setMode(uint value) external {mode=value;}
 mapping(address=>uint) public balanceOf;mapping(address=>mapping(address=>uint)) public allowance;
 function mint(address to,uint value) external {balanceOf[to]+=value;}
 function burn(address from,uint value) external {balanceOf[from]-=value;}
 function approve(address to,uint value) external returns(bool){allowance[msg.sender][to]=value;return true;}
 function transfer(address to,uint value) external returns(bool){balanceOf[msg.sender]-=value;balanceOf[to]+=value;if(mode==1)return false;if(mode==2)assembly{return(0,0)}if(mode==3)revert("token failure");return true;}
 function transferFrom(address from,address to,uint value) external returns(bool){if(msg.sender!=from&&allowance[from][msg.sender]!=type(uint).max)allowance[from][msg.sender]-=value;balanceOf[from]-=value;balanceOf[to]+=value;if(mode==1)return false;if(mode==2)assembly{return(0,0)}if(mode==3)revert("token failure");return true;}
 function deposit() external payable {balanceOf[msg.sender]+=msg.value;}
 function withdraw(uint amount) external {balanceOf[msg.sender]-=amount;(bool ok,)=msg.sender.call{value:amount}("");require(ok);}
}
contract LZDeps is IExchange {
 using SafeERC20 for IERC20;
 LZToken public WETH=new LZToken();LZToken public collateral=new LZToken();LZToken public boldToken=new LZToken();
 address public boOverride;function setBorrower(address target) external {boOverride=target;}
 address public owner;address public receiver;uint public coll;uint public debt;uint public lastIndex;uint public lastRate;bool public batched;bool public closed;
 uint public fee=1;uint public extra=17;bool public failSwap;
 function setFailSwap(bool flag) external {failSwap=flag;}
 constructor(address borrower,bool lst){owner=borrower;if(!lst)collateral=WETH;}
 function troveNFT() external view returns(address){return address(this);}
 function borrowerOperations() external view returns(address){return boOverride==address(0)?address(this):boOverride;}
 function troveManager() external view returns(address){return address(this);}
 function collToken() external view returns(address){return address(collateral);}
 function ownerOf(uint) external view returns(address){return owner;}
 function setOwner(address who) external {owner=who;}
 function setReceiver(address who) external {receiver=who;}
 function removeManagerReceiverOf(uint) external view returns(address,address){return(receiver,receiver);}
 function getLatestTroveData(uint) external view returns(LatestTroveData memory t){t.entireDebt=debt;t.entireColl=coll;}
 function openTrove(address o,uint index,uint c,uint b,uint,uint,uint rate,uint,address add,address remove,address r) external returns(uint){require(add==msg.sender&&remove==msg.sender&&r==msg.sender,"zapper managers");owner=o;lastIndex=index;lastRate=rate;receiver=r;coll=c;debt=b;WETH.transferFrom(msg.sender,address(this),375e14);IERC20(address(collateral)).safeTransferFrom(msg.sender,address(this),c);boldToken.mint(msg.sender,b);return 1;}
 function openTroveAndJoinInterestBatchManager(IBorrowerOperations.OpenTroveAndJoinInterestBatchManagerParams calldata p) external returns(uint){owner=p.owner;lastIndex=p.ownerIndex;receiver=p.receiver;coll=p.collAmount;debt=p.boldAmount;batched=true;WETH.transferFrom(msg.sender,address(this),375e14);IERC20(address(collateral)).safeTransferFrom(msg.sender,address(this),p.collAmount);boldToken.mint(msg.sender,p.boldAmount);return 1;}
 function addColl(uint,uint amount) external {IERC20(address(collateral)).safeTransferFrom(msg.sender,address(this),amount);coll+=amount;}
 function withdrawColl(uint,uint amount) external {coll-=amount;IERC20(address(collateral)).safeTransfer(msg.sender,amount);}
 function withdrawBold(uint,uint amount,uint) external {debt+=amount;boldToken.mint(msg.sender,amount);}
 function repayBold(uint,uint amount) external {uint repayment=amount>debt-2000e18?debt-2000e18:amount;debt-=repayment;boldToken.burn(msg.sender,repayment);}
 function adjustment(uint c,bool increase,uint b,bool debtIncrease) internal {
  if(increase){IERC20(address(collateral)).safeTransferFrom(msg.sender,address(this),c);coll+=c;}else{coll-=c;IERC20(address(collateral)).safeTransfer(msg.sender,c);}
  if(debtIncrease){debt+=b;boldToken.mint(msg.sender,b);}else{uint repay=b>debt-2000e18?debt-2000e18:b;debt-=repay;boldToken.burn(msg.sender,repay);}
 }
 function adjustTrove(uint,uint c,bool increase,uint b,bool debtIncrease,uint) external {adjustment(c,increase,b,debtIncrease);}
 function adjustZombieTrove(uint,uint c,bool increase,uint b,bool debtIncrease,uint,uint,uint) external {adjustment(c,increase,b,debtIncrease);}
 function closeTrove(uint) external {boldToken.burn(msg.sender,debt);IERC20(address(collateral)).safeTransfer(msg.sender,coll);WETH.transfer(msg.sender,375e14);coll=0;debt=0;closed=true;}
 function makeFlashLoan(address token,uint amount,IFlashLoanProvider.Operation operation,bytes calldata data) external {
  require(token==address(collateral));uint effective=amount-fee;
  collateral.mint(msg.sender,effective);
  IFlashLoanReceiver z=IFlashLoanReceiver(msg.sender);
  if(operation==IFlashLoanProvider.Operation.OpenTrove)z.receiveFlashLoanOnOpenLeveragedTrove(abi.decode(data,(ILeverageZapper.OpenLeveragedTroveParams)),effective);
  else if(operation==IFlashLoanProvider.Operation.LeverUpTrove)z.receiveFlashLoanOnLeverUpTrove(abi.decode(data,(ILeverageZapper.LeverUpTroveParams)),effective);
  else if(operation==IFlashLoanProvider.Operation.LeverDownTrove)z.receiveFlashLoanOnLeverDownTrove(abi.decode(data,(ILeverageZapper.LeverDownTroveParams)),effective);
  else z.receiveFlashLoanOnCloseTroveFromCollateral(abi.decode(data,(IZapper.CloseTroveParams)),effective);
 }
 function swapFromBold(uint amount,uint minimum) external{require(!failSwap,"swap failure");boldToken.transferFrom(msg.sender,address(this),amount);collateral.mint(msg.sender,minimum+extra);}
 function swapToBold(uint amount,uint minimum) external returns(uint){require(!failSwap,"swap failure");IERC20(address(collateral)).safeTransferFrom(msg.sender,address(this),amount);boldToken.mint(msg.sender,minimum);return minimum;}
}

contract LeverageZapperParityTest {
 LZVm constant vm=LZVm(address(uint160(uint(keccak256("hevm cheat code")))));
 receive() external payable {}
 function make(bool fe,bool lst) internal returns(ILeverageZapper z,LZDeps d){return makeExchange(fe,lst,address(0));}
 function makeExchange(bool fe,bool lst,address exchange) internal returns(ILeverageZapper z,LZDeps d){
  d=new LZDeps(address(this),lst);vm.deal(address(d.WETH()),1000e18);
  bytes memory code=fe?vm.parseBytes(vm.readFile(lst?"build/LeverageLSTZapper.bin":"build/LeverageWETHZapper.bin")):(lst?type(LeverageLSTZapper).creationCode:type(LeverageWETHZapper).creationCode);
  bytes memory init=bytes.concat(code,abi.encode(d,d,exchange==address(0)?address(d):exchange));require(init.length<=49152,"initcode size");address created;assembly{created:=create(0,add(init,32),mload(init))}require(created.code.length>0&&created.code.length<=24576,"deploy");z=ILeverageZapper(created);
  if(fe){address companion=address(uint160(uint(keccak256(abi.encodePacked(hex"d694",created,hex"01")))));require(companion.code.length>0&&companion.code.length<=24576,"companion size");}
  d.boldToken().approve(created,type(uint).max);d.collateral().approve(created,type(uint).max);d.collateral().mint(address(this),100e18);
 }
 function params(bool batch) internal view returns(ILeverageZapper.OpenLeveragedTroveParams memory p){p.owner=address(this);p.ownerIndex=17;p.collAmount=10e18;p.flashLoanAmount=5e18;p.boldAmount=3000e18;p.annualInterestRate=batch?0:5e16;p.batchManager=batch?address(123):address(0);p.maxUpfrontFee=1e18;}
 function run(bool fe,bool lst,bool batch,uint index) internal returns(bytes32){
  (ILeverageZapper z,LZDeps d)=make(fe,lst);vm.deal(address(this),100e18);
  d.boldToken().mint(address(z),123);d.collateral().mint(address(z),456);
  ILeverageZapper.OpenLeveragedTroveParams memory p=params(batch);p.ownerIndex=index;
  z.openLeveragedTroveWithRawETH{value:375e14+(lst?0:p.collAmount)}(p);
  require(d.coll()==15e18-1&&d.debt()==3000e18&&d.batched()==batch,"open state");
  require(d.lastIndex()==uint(keccak256(abi.encode(address(this),index))),"index");
  require(d.boldToken().balanceOf(address(z))==123&&d.collateral().balanceOf(address(z))==456,"preserve baseline");
  z.leverUpTrove(ILeverageZapper.LeverUpTroveParams(1,2e18,500e18,1e18));
  require(d.coll()==17e18-2&&d.debt()==3500e18,"up state");
  z.leverDownTrove(ILeverageZapper.LeverDownTroveParams(1,1e18,300e18));
  require(d.coll()==16e18-2&&d.debt()==3200e18,"down state");
  require(d.boldToken().balanceOf(address(z))==123&&d.collateral().balanceOf(address(z))==456,"leftovers");
  d.boldToken().mint(address(this),d.debt());
  GasCompZapper(payable(address(z))).closeTroveToRawETH(1);require(d.closed(),"inherited close");
  return keccak256(abi.encode(address(this).balance,d.boldToken().balanceOf(address(this)),d.collateral().balanceOf(address(this)),d.boldToken().balanceOf(address(z)),d.collateral().balanceOf(address(z))));
 }
 function testIndividualAndBatchLeverageLifecycleBothBranches() public {for(uint i;i<4;i++)require(run(true,i%2==1,i>1,17)==run(false,i%2==1,i>1,17),"parity");}
 function testFuzzLeveragedOwnerIndex(uint index,bool lst,bool batch) public {require(run(true,lst,batch,index)==run(false,lst,batch,index),"fuzz parity");}
 function compare(ILeverageZapper a,ILeverageZapper b,bytes memory data,uint value) internal returns(bool){(bool ok,bytes memory x)=address(a).call{value:value}(data);(bool success,bytes memory y)=address(b).call{value:value}(data);require(ok==success&&keccak256(x)==keccak256(y),"return parity");return ok;}
 function testMemoryAddressValidationAndUnauthorizedCallbacks() public {
  for(uint branch;branch<2;branch++){
   (ILeverageZapper a,)=make(true,branch==1);(ILeverageZapper b,)=make(false,branch==1);vm.deal(address(this),100e18);
   bytes memory data;
   uint[5] memory offsets=[uint(0),8,10,11,12];
   for(uint i;i<5;i++){
    data=abi.encodeCall(a.openLeveragedTroveWithRawETH,(params(false)));uint offset=36+offsets[i]*32;
    assembly{mstore(add(data,offset),not(0))}require(!compare(a,b,data,0));
   }
   require(!compare(a,b,abi.encodePacked(a.openLeveragedTroveWithRawETH.selector),0));
   data=abi.encodeCall(IFlashLoanReceiver.receiveFlashLoanOnOpenLeveragedTrove,(params(false),5e18));
   assembly{mstore(add(data,36),not(0))}require(!compare(a,b,data,0));
   require(!compare(a,b,abi.encodeCall(IFlashLoanReceiver.receiveFlashLoanOnLeverUpTrove,(ILeverageZapper.LeverUpTroveParams(1,2e18,500e18,1e18),2e18)),0));
   require(!compare(a,b,abi.encodeCall(IFlashLoanReceiver.receiveFlashLoanOnLeverDownTrove,(ILeverageZapper.LeverDownTroveParams(1,1e18,300e18),1e18)),0));
  }
 }
 function testSwapFailureRollsBackOpenAndUp() public {
  for(uint branch;branch<2;branch++){
   bool lst=branch==1;(ILeverageZapper a,LZDeps da)=make(true,lst);(ILeverageZapper b,LZDeps db)=make(false,lst);vm.deal(address(this),100e18);
   bytes memory data=abi.encodeCall(a.openLeveragedTroveWithRawETH,(params(false)));uint value=375e14+(lst?0:10e18);
   da.setFailSwap(true);db.setFailSwap(true);require(!compare(a,b,data,value));require(da.coll()==0&&db.coll()==0,"open rollback");
   da.setFailSwap(false);db.setFailSwap(false);require(compare(a,b,data,value));
   da.setFailSwap(true);db.setFailSwap(true);data=abi.encodeCall(a.leverUpTrove,(ILeverageZapper.LeverUpTroveParams(1,2e18,500e18,1e18)));require(!compare(a,b,data,0));require(da.coll()==15e18-1&&db.coll()==15e18-1&&da.debt()==3000e18&&db.debt()==3000e18,"up rollback");
  }
 }
 function testFuzzLeverageRatio(uint ratio,bool lst) public {
  (ILeverageZapper a,)=make(true,lst);(ILeverageZapper b,)=make(false,lst);
  compare(a,b,abi.encodeCall(a.leverageRatioToCollateralRatio,(ratio)),0);
 }
 function testRatioBoundaries() public {
  (ILeverageZapper a,)=make(true,false);(ILeverageZapper b,)=make(false,false);
  uint[6] memory values=[uint(0),1e18-1,1e18,1e18+1,2e18,type(uint).max];
  for(uint i;i<values.length;i++)compare(a,b,abi.encodeCall(a.leverageRatioToCollateralRatio,(values[i])),0);
 }
 function testOwnerAndReceiverChecksAndWrongValue() public {
  for(uint branch;branch<2;branch++){
   bool lst=branch==1;(ILeverageZapper a,LZDeps da)=make(true,lst);(ILeverageZapper b,LZDeps db)=make(false,lst);vm.deal(address(this),100e18);
   bytes memory opening=abi.encodeCall(a.openLeveragedTroveWithRawETH,(params(false)));uint value=375e14+(lst?0:10e18);
   require(!compare(a,b,opening,value+1));require(compare(a,b,opening,value));
   bytes memory data=abi.encodeCall(a.leverUpTrove,(ILeverageZapper.LeverUpTroveParams(1,2e18,500e18,1e18)));
   da.setOwner(address(123));db.setOwner(address(123));require(!compare(a,b,data,0));
   da.setOwner(address(this));db.setOwner(address(this));da.setReceiver(address(123));db.setReceiver(address(123));require(!compare(a,b,data,0));
  }
 }
 function testMissingExchangeCodeRollsBackOpen() public {
  for(uint branch;branch<2;branch++){
   bool lst=branch==1;(ILeverageZapper a,LZDeps da)=makeExchange(true,lst,address(0xdead));(ILeverageZapper b,LZDeps db)=makeExchange(false,lst,address(0xdead));vm.deal(address(this),100e18);
   require(!compare(a,b,abi.encodeCall(a.openLeveragedTroveWithRawETH,(params(false))),375e14+(lst?0:10e18)));
   require(da.coll()==0&&db.coll()==0&&da.debt()==0&&db.debt()==0,"missing exchange rollback");
  }
 }
}
