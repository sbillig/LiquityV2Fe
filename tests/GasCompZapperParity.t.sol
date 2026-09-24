// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {GasCompZapper,IAddressesRegistry,IFlashLoanProvider,IExchange,IBorrowerOperations,LatestTroveData} from "../reference/bold/contracts/src/Zappers/GasCompZapper.sol";
import {IZapper} from "../reference/bold/contracts/src/Zappers/Interfaces/IZapper.sol";
import {IERC20,SafeERC20} from "../reference/bold/contracts/lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
interface GCZVm {function readFile(string calldata) external view returns(string memory);function parseBytes(string calldata) external pure returns(bytes memory);function deal(address,uint) external;}
contract GCZToken {
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
contract GCZDeps {
 using SafeERC20 for IERC20;
 GCZToken public WETH=new GCZToken();GCZToken public collateral=new GCZToken();GCZToken public boldToken=new GCZToken();
 address public boOverride;function setBorrower(address target) external {boOverride=target;}
 address public owner;address public receiver;uint public coll;uint public debt;uint public lastIndex;uint public lastRate;bool public batched;bool public closed;
 constructor(address borrower){owner=borrower;}
 function troveNFT() external view returns(address){return address(this);}
 function borrowerOperations() external view returns(address){return boOverride==address(0)?address(this):boOverride;}
 function troveManager() external view returns(address){return address(this);}
 function collToken() external view returns(address){return address(collateral);}
 function ownerOf(uint) external view returns(address){return owner;}
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
  require(token==address(collateral)&&operation==IFlashLoanProvider.Operation.CloseTrove);collateral.mint(msg.sender,amount);
  GasCompZapper(payable(msg.sender)).receiveFlashLoanOnCloseTroveFromCollateral(abi.decode(data,(IZapper.CloseTroveParams)),amount-1);
 }
 function swapToBold(uint amount,uint minimum) external returns(uint){IERC20(address(collateral)).safeTransferFrom(msg.sender,address(this),amount);boldToken.mint(msg.sender,minimum);return minimum;}
}
contract GasCompZapperParityTest {
 GCZVm constant vm=GCZVm(address(uint160(uint(keccak256("hevm cheat code")))));
 bool rejectETH;receive() external payable {require(!rejectETH,"reject ETH");}
 function make(bool fe) internal returns(GasCompZapper z,GCZDeps d){
  d=new GCZDeps(address(this));vm.deal(address(d.WETH()),1000e18);
  bytes memory code=fe?vm.parseBytes(vm.readFile("build/GasCompZapper.bin")):type(GasCompZapper).creationCode;
  bytes memory init=bytes.concat(code,abi.encode(d,d,d));address created;assembly{created:=create(0,add(init,32),mload(init))}require(created.code.length>0&&created.code.length<=24576,"deploy");z=GasCompZapper(payable(created));
  d.boldToken().approve(created,type(uint).max);d.collateral().approve(created,type(uint).max);d.collateral().mint(address(this),100e18);
 }
 function params() internal view returns(IZapper.OpenTroveParams memory p){p.owner=address(this);p.ownerIndex=17;p.collAmount=10e18;p.boldAmount=3000e18;p.annualInterestRate=5e16;p.maxUpfrontFee=1e18;}
 function run(bool fe,bool batch,bool flash) internal returns(bytes32){
  (GasCompZapper z,GCZDeps d)=make(fe);vm.deal(address(this),100e18);
  IZapper.OpenTroveParams memory p=params();if(batch){p.batchManager=address(123);p.annualInterestRate=0;}
  require(z.openTroveWithRawETH{value:375e14}(p)==1);require(d.coll()==10e18&&d.debt()==3000e18);
  require(d.lastIndex()==uint(keccak256(abi.encode(address(this),uint(17)))));require(d.batched()==batch);
  z.addColl(1,2e18);z.withdrawColl(1,1e18);z.withdrawBold(1,500e18,1e18);
  d.boldToken().mint(address(z),123);d.collateral().mint(address(z),456);d.WETH().mint(address(z),789);
  z.repayBold(1,2000e18);require(d.debt()==2000e18);require(d.boldToken().balanceOf(address(z))==123);
  z.adjustTrove(1,1e18,true,300e18,true,1e18);
  z.adjustZombieTrove(1,1e18,false,500e18,false,0,0,1e18);require(d.debt()==2000e18);
  if(flash)z.closeTroveFromCollateral(1,1e18,10e18);else z.closeTroveToRawETH(1);
  require(d.closed()&&d.coll()==0&&d.debt()==0);require(d.boldToken().balanceOf(address(z))==123&&d.collateral().balanceOf(address(z))==456&&d.WETH().balanceOf(address(z))==789);
  return keccak256(abi.encode(address(this).balance,d.boldToken().balanceOf(address(this)),d.collateral().balanceOf(address(this)),d.boldToken().balanceOf(address(z)),d.collateral().balanceOf(address(z))));
 }
 function testLifecycleIndividualBatchAndFlashClose() public {for(uint i;i<4;i++)require(run(true,i%2==1,i>1)==run(false,i%2==1,i>1),"state parity");}
 function compare(GasCompZapper a,GasCompZapper b,bytes memory data,uint value) internal returns(bool){(bool ok,bytes memory x)=address(a).call{value:value}(data);(bool success,bytes memory y)=address(b).call{value:value}(data);require(ok==success&&keccak256(x)==keccak256(y),"return parity");return ok;}
 function testETHAndBatchErrorsAndNonpayableAdjustments() public {
  (GasCompZapper a,)=make(true);(GasCompZapper b,)=make(false);vm.deal(address(this),100e18);
  require(compare(a,b,"",1e18));require(!compare(a,b,hex"1234",1));
  IZapper.OpenTroveParams memory p=params();require(!compare(a,b,abi.encodeCall(a.openTroveWithRawETH,(p)),375e14+1));
  p.batchManager=address(123);require(!compare(a,b,abi.encodeCall(a.openTroveWithRawETH,(p)),375e14));p.batchManager=address(0);
  require(compare(a,b,abi.encodeCall(a.openTroveWithRawETH,(p)),375e14));
  require(!compare(a,b,abi.encodeCall(a.addColl,(1,2e18)),1));
  require(!compare(a,b,abi.encodeCall(a.adjustTrove,(1,2e18,true,0,false,1e18)),1));
  require(compare(a,b,abi.encodeCall(a.setAddManager,(1,address(55))),0));require(compare(a,b,abi.encodeCall(a.addManagerOf,(1)),0));
 }
 function testOptionalTokenReturnsAndRollback() public {
  (GasCompZapper a,GCZDeps da)=make(true);(GasCompZapper b,GCZDeps db)=make(false);vm.deal(address(this),100e18);
  IZapper.OpenTroveParams memory p=params();require(compare(a,b,abi.encodeCall(a.openTroveWithRawETH,(p)),375e14));
  da.collateral().setMode(1);db.collateral().setMode(1);require(!compare(a,b,abi.encodeCall(a.addColl,(1,1e18)),0));
  require(da.coll()==10e18&&db.coll()==10e18,"rollback");
  da.collateral().setMode(2);db.collateral().setMode(2);require(compare(a,b,abi.encodeCall(a.withdrawColl,(1,1e18)),0));
  da.collateral().setMode(0);db.collateral().setMode(0);
  rejectETH=true;require(!compare(a,b,abi.encodeCall(a.closeTroveToRawETH,(1)),0));rejectETH=false;
  require(da.coll()==9e18&&db.coll()==9e18,"ETH rollback");
 }
 function openFuzz(bool fe,uint index,uint value,uint amount,bool batch) internal returns(bytes32){
  (GasCompZapper z,GCZDeps d)=make(fe);vm.deal(address(this),375e14);
  IZapper.OpenTroveParams memory p=params();p.ownerIndex=index;p.boldAmount=amount;p.collAmount=value;
  if(batch){p.batchManager=address(123);p.annualInterestRate=0;}
  z.openTroveWithRawETH{value:375e14}(p);
  require(d.lastIndex()==uint(keccak256(abi.encode(address(this),index))),"owner index");
  return keccak256(abi.encode(d.coll(),d.debt(),d.lastIndex(),d.lastRate(),d.batched(),d.boldToken().balanceOf(address(this)),d.collateral().balanceOf(address(z)),z.addManagerOf(1)));
 }
 function testFuzzOpeningIndexAndCollateral(uint index,uint64 collateral,uint96 bold,bool batch) public {
  require(openFuzz(true,index,uint(collateral),uint(bold),batch)==openFuzz(false,index,uint(collateral),uint(bold),batch),"opening parity");
 }
 function testNoOpCallbackBoundsAndLazyAddressValidation() public {
  (GasCompZapper a,)=make(true);(GasCompZapper b,)=make(false);
  bytes4 selector=bytes4(keccak256("receiveFlashLoanOnOpenLeveragedTrove((address,uint256,uint256,uint256,uint256,uint256,uint256,uint256,address,uint256,address,address,address),uint256)"));
  bytes memory data=new bytes(4+14*32);assembly{mstore(add(data,32),and(selector,shl(224,0xffffffff)))}
  require(compare(a,b,data,0));
  assembly{mstore(add(data,36),not(0))}require(compare(a,b,data,0));
  require(!compare(a,b,abi.encodePacked(selector),0));
 }
 function testCalldataStructValidationOrder() public {
  (GasCompZapper a,)=make(true);(GasCompZapper b,)=make(false);vm.deal(address(this),100e18);
  bytes memory data=abi.encodeCall(a.openTroveWithRawETH,(params()));
  assembly{mstore(add(data,36),not(0))}
  require(!compare(a,b,data,375e14+1));require(!compare(a,b,data,375e14));
  IZapper.CloseTroveParams memory p=IZapper.CloseTroveParams(1,1e18,0,address(this));
  data=abi.encodeCall(a.receiveFlashLoanOnCloseTroveFromCollateral,(p,1e18));
  assembly{mstore(add(data,132),not(0))}require(!compare(a,b,data,0));
 }
}
