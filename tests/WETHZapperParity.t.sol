// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {WETHZapper,IAddressesRegistry,IFlashLoanProvider,IExchange,IBorrowerOperations,LatestTroveData} from "../reference/bold/contracts/src/Zappers/WETHZapper.sol";
import {IZapper} from "../reference/bold/contracts/src/Zappers/Interfaces/IZapper.sol";
interface WZVm {function readFile(string calldata) external view returns(string memory);function parseBytes(string calldata) external pure returns(bytes memory);function deal(address,uint) external;function etch(address,bytes calldata) external;function prank(address) external;}
contract WZToken {
 mapping(address=>uint) public balanceOf;mapping(address=>mapping(address=>uint)) public allowance;
 function mint(address to,uint value) external {balanceOf[to]+=value;}
 function burn(address from,uint value) external {balanceOf[from]-=value;}
 function approve(address to,uint value) external returns(bool){allowance[msg.sender][to]=value;return true;}
 function transfer(address to,uint value) external returns(bool){balanceOf[msg.sender]-=value;balanceOf[to]+=value;return true;}
 function transferFrom(address from,address to,uint value) external returns(bool){if(msg.sender!=from&&allowance[from][msg.sender]!=type(uint).max)allowance[from][msg.sender]-=value;balanceOf[from]-=value;balanceOf[to]+=value;return true;}
 function deposit() external payable {balanceOf[msg.sender]+=msg.value;}
 function withdraw(uint amount) external {balanceOf[msg.sender]-=amount;(bool ok,)=msg.sender.call{value:amount}("");require(ok);}
}
contract WZDeps {
 WZToken public WETH=new WZToken();WZToken public boldToken=new WZToken();
 address public boOverride;function setBorrower(address target) external {boOverride=target;}
 address public owner;address public receiver;uint public coll;uint public debt;uint public lastIndex;uint public lastRate;bool public batched;bool public closed;
 constructor(address borrower){owner=borrower;}
 function troveNFT() external view returns(address){return address(this);}
 function borrowerOperations() external view returns(address){return boOverride==address(0)?address(this):boOverride;}
 function troveManager() external view returns(address){return address(this);}
 function collToken() external view returns(address){return address(WETH);}
 function ownerOf(uint) external view returns(address){return owner;}
 function removeManagerReceiverOf(uint) external view returns(address,address){return(receiver,receiver);}
 function getLatestTroveData(uint) external view returns(LatestTroveData memory t){t.entireDebt=debt;t.entireColl=coll;}
 function openTrove(address o,uint index,uint c,uint b,uint,uint,uint rate,uint,address add,address remove,address r) external returns(uint){require(add==msg.sender&&remove==msg.sender&&r==msg.sender,"zapper managers");owner=o;lastIndex=index;lastRate=rate;receiver=r;coll=c;debt=b;WETH.transferFrom(msg.sender,address(this),c+375e14);boldToken.mint(msg.sender,b);return 1;}
 function openTroveAndJoinInterestBatchManager(IBorrowerOperations.OpenTroveAndJoinInterestBatchManagerParams calldata p) external returns(uint){owner=p.owner;lastIndex=p.ownerIndex;receiver=p.receiver;coll=p.collAmount;debt=p.boldAmount;batched=true;WETH.transferFrom(msg.sender,address(this),p.collAmount+375e14);boldToken.mint(msg.sender,p.boldAmount);return 1;}
 function addColl(uint,uint amount) external {WETH.transferFrom(msg.sender,address(this),amount);coll+=amount;}
 function withdrawColl(uint,uint amount) external {coll-=amount;WETH.transfer(msg.sender,amount);}
 function withdrawBold(uint,uint amount,uint) external {debt+=amount;boldToken.mint(msg.sender,amount);}
 function repayBold(uint,uint amount) external {uint repayment=amount>debt-2000e18?debt-2000e18:amount;debt-=repayment;boldToken.burn(msg.sender,repayment);}
 function adjustment(uint c,bool increase,uint b,bool debtIncrease) internal {
  if(increase){WETH.transferFrom(msg.sender,address(this),c);coll+=c;}else{coll-=c;WETH.transfer(msg.sender,c);}
  if(debtIncrease){debt+=b;boldToken.mint(msg.sender,b);}else{uint repay=b>debt-2000e18?debt-2000e18:b;debt-=repay;boldToken.burn(msg.sender,repay);}
 }
 function adjustTrove(uint,uint c,bool increase,uint b,bool debtIncrease,uint) external {adjustment(c,increase,b,debtIncrease);}
 function adjustZombieTrove(uint,uint c,bool increase,uint b,bool debtIncrease,uint,uint,uint) external {adjustment(c,increase,b,debtIncrease);}
 function closeTrove(uint) external {boldToken.burn(msg.sender,debt);WETH.transfer(msg.sender,coll+375e14);coll=0;debt=0;closed=true;}
 function makeFlashLoan(address token,uint amount,IFlashLoanProvider.Operation operation,bytes calldata data) external {
  require(token==address(WETH)&&operation==IFlashLoanProvider.Operation.CloseTrove);WETH.mint(msg.sender,amount);
  WETHZapper(payable(msg.sender)).receiveFlashLoanOnCloseTroveFromCollateral(abi.decode(data,(IZapper.CloseTroveParams)),amount-1);
 }
 function swapToBold(uint amount,uint minimum) external returns(uint){WETH.transferFrom(msg.sender,address(this),amount);boldToken.mint(msg.sender,minimum);return minimum;}
}
contract WETHZapperParityTest {
 WZVm constant vm=WZVm(address(uint160(uint(keccak256("hevm cheat code")))));
 bool rejectETH;receive() external payable {require(!rejectETH,"reject ETH");}
 function make(bool fe) internal returns(WETHZapper z,WZDeps d){
  d=new WZDeps(address(this));vm.deal(address(d.WETH()),1000e18);
  bytes memory code=fe?vm.parseBytes(vm.readFile("build/WETHZapper.bin")):type(WETHZapper).creationCode;
  bytes memory init=bytes.concat(code,abi.encode(d,d,d));address created;assembly{created:=create(0,add(init,32),mload(init))}require(created.code.length>0&&created.code.length<=24576,"deploy");z=WETHZapper(payable(created));d.boldToken().approve(created,type(uint).max);
 }
 function params() internal view returns(IZapper.OpenTroveParams memory p){p.owner=address(this);p.ownerIndex=17;p.collAmount=777;p.boldAmount=3000e18;p.annualInterestRate=5e16;p.maxUpfrontFee=1e18;}
 function run(bool fe,bool batch,bool flash) internal returns(bytes32){
  (WETHZapper z,WZDeps d)=make(fe);vm.deal(address(this),100e18);
  IZapper.OpenTroveParams memory p=params();if(batch){p.batchManager=address(123);p.annualInterestRate=0;}
  require(z.openTroveWithRawETH{value:10e18+375e14}(p)==1);require(d.coll()==10e18&&d.debt()==3000e18);
  require(d.lastIndex()==uint(keccak256(abi.encode(address(this),uint(17)))));require(d.batched()==batch);
  z.addCollWithRawETH{value:2e18}(1);z.withdrawCollToRawETH(1,1e18);z.withdrawBold(1,500e18,1e18);
  d.boldToken().mint(address(z),123);d.WETH().mint(address(z),456);
  z.repayBold(1,2000e18);require(d.debt()==2000e18);require(d.boldToken().balanceOf(address(z))==123);
  z.adjustTroveWithRawETH{value:1e18}(1,1e18,true,300e18,true,1e18);
  z.adjustZombieTroveWithRawETH(1,1e18,false,500e18,false,0,0,1e18);require(d.debt()==2000e18);
  if(flash)z.closeTroveFromCollateral(1,1e18,10e18);else z.closeTroveToRawETH(1);
  require(d.closed()&&d.coll()==0&&d.debt()==0);require(d.boldToken().balanceOf(address(z))==123&&d.WETH().balanceOf(address(z))==456);
  return keccak256(abi.encode(address(this).balance,d.boldToken().balanceOf(address(this)),d.WETH().balanceOf(address(this)),d.boldToken().balanceOf(address(z)),d.WETH().balanceOf(address(z))));
 }
 function testLifecycleIndividualBatchAndFlashClose() public {for(uint i;i<4;i++)require(run(true,i%2==1,i>1)==run(false,i%2==1,i>1),"state parity");}
 function callBoth(WETHZapper a,WETHZapper b,bytes memory data,uint value) internal returns(bool){(bool ok,bytes memory x)=address(a).call{value:value}(data);(bool success,bytes memory y)=address(b).call{value:value}(data);require(ok==success&&keccak256(x)==keccak256(y),"return parity");return ok;}
 function testMissingBorrowerCodeRevertsAndRollsBackDeposit() public {
  vm.deal(address(this),100e18);
  WZDeps d=new WZDeps(address(this));d.setBorrower(address(0xdead));
  bytes memory init=bytes.concat(vm.parseBytes(vm.readFile("build/WETHZapper.bin")),abi.encode(d,d,d));
  address created;assembly{created:=create(0,add(init,32),mload(init))}require(created.code.length>0);
  WETHZapper a=WETHZapper(payable(created));WETHZapper b=new WETHZapper(IAddressesRegistry(address(d)),IFlashLoanProvider(address(d)),IExchange(address(d)));
  require(!callBoth(a,b,abi.encodeCall(a.addCollWithRawETH,(1)),1e18));
  require(d.WETH().balanceOf(address(a))==0&&d.WETH().balanceOf(address(b))==0);
 }
 function testETHSendFailureRollsBack() public {
  (WETHZapper a,WZDeps da)=make(true);(WETHZapper b,WZDeps db)=make(false);vm.deal(address(this),100e18);
  IZapper.OpenTroveParams memory p=params();require(callBoth(a,b,abi.encodeCall(a.openTroveWithRawETH,(p)),10e18+375e14));
  rejectETH=true;require(!callBoth(a,b,abi.encodeCall(a.withdrawCollToRawETH,(1,1e18)),0));rejectETH=false;
  require(da.coll()==10e18&&db.coll()==10e18,"ETH rollback");
 }
 function openFuzz(bool fe,uint index,uint value,uint amount,bool batch) internal returns(bytes32){
  (WETHZapper z,WZDeps d)=make(fe);vm.deal(address(this),value);
  IZapper.OpenTroveParams memory p=params();p.ownerIndex=index;p.boldAmount=amount;
  if(batch){p.batchManager=address(123);p.annualInterestRate=0;}
  z.openTroveWithRawETH{value:value}(p);
  require(d.lastIndex()==uint(keccak256(abi.encode(address(this),index))),"owner index");
  return keccak256(abi.encode(d.coll(),d.debt(),d.lastIndex(),d.lastRate(),d.batched(),d.boldToken().balanceOf(address(this)),d.WETH().balanceOf(address(z)),z.addManagerOf(1)));
 }
 function testFuzzOpeningIndexAndValue(uint index,uint64 collateral,uint96 bold,bool batch) public {
  uint value=uint(collateral)+375e14+1;
  require(openFuzz(true,index,value,uint(bold),batch)==openFuzz(false,index,value,uint(bold),batch),"opening parity");
 }
 function testNoOpCallbackBoundsAndLazyAddressValidation() public {
  (WETHZapper a,)=make(true);(WETHZapper b,)=make(false);
  bytes4 selector=bytes4(keccak256("receiveFlashLoanOnOpenLeveragedTrove((address,uint256,uint256,uint256,uint256,uint256,uint256,uint256,address,uint256,address,address,address),uint256)"));
  bytes memory data=new bytes(4+14*32);assembly{mstore(add(data,32),and(selector,shl(224,0xffffffff)))}
  require(callBoth(a,b,data,0));
  assembly{mstore(add(data,36),not(0))}require(callBoth(a,b,data,0));
  require(!callBoth(a,b,abi.encodePacked(selector),0));
 }
 function testCalldataStructValidationOrder() public {
  (WETHZapper a,)=make(true);(WETHZapper b,)=make(false);vm.deal(address(this),100e18);
  bytes memory data=abi.encodeCall(a.openTroveWithRawETH,(params()));
  assembly{mstore(add(data,36),not(0))}
  require(!callBoth(a,b,data,375e14));require(!callBoth(a,b,data,10e18));
  IZapper.CloseTroveParams memory p=IZapper.CloseTroveParams(1,1e18,0,address(this));
  data=abi.encodeCall(a.receiveFlashLoanOnCloseTroveFromCollateral,(p,1e18));
  assembly{mstore(add(data,132),not(0))}require(!callBoth(a,b,data,0));
 }
 function testErrorsReceiveAndManagers() public {
  (WETHZapper a,)=make(true);(WETHZapper b,)=make(false);vm.deal(address(this),100e18);
  require(callBoth(a,b,"",1e18));require(!callBoth(a,b,hex"1234",1));
  IZapper.OpenTroveParams memory p=params();require(!callBoth(a,b,abi.encodeCall(a.openTroveWithRawETH,(p)),375e14));
  p.batchManager=address(123);require(!callBoth(a,b,abi.encodeCall(a.openTroveWithRawETH,(p)),1e18));p.batchManager=address(0);
  require(callBoth(a,b,abi.encodeCall(a.openTroveWithRawETH,(p)),10e18+375e14));
  require(!callBoth(a,b,abi.encodeCall(a.adjustTroveWithRawETH,(1,2e18,true,0,false,1e18)),1e18));
  require(!callBoth(a,b,abi.encodeCall(a.adjustTroveWithRawETH,(1,2e18,false,0,false,1e18)),1e18));
  require(callBoth(a,b,abi.encodeCall(a.setAddManager,(1,address(55))),0));require(callBoth(a,b,abi.encodeCall(a.addManagerOf,(1)),0));
  require(callBoth(a,b,abi.encodeCall(a.setRemoveManagerWithReceiver,(1,address(66),address(77))),0));require(callBoth(a,b,abi.encodeCall(a.removeManagerReceiverOf,(1)),0));
  IZapper.CloseTroveParams memory close=IZapper.CloseTroveParams(1,1e18,0,address(this));require(!callBoth(a,b,abi.encodeCall(a.receiveFlashLoanOnCloseTroveFromCollateral,(close,1e18)),0));
 }
}
