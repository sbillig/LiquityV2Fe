// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {RedemptionHelper,ICollateralRegistry,IAddressesRegistry,LatestTroveData} from "../reference/bold/contracts/src/RedemptionHelper.sol";
interface RHVm {
 function readFile(string calldata) external view returns(string memory);
 function parseBytes(string calldata) external pure returns(bytes memory);
 function load(address,bytes32) external view returns(bytes32);
}
contract RHToken {
 mapping(address=>uint) public balanceOf;
 uint public mode;
 function setMode(uint m) external {mode=m;}
 function mint(address to,uint value) external {balanceOf[to]+=value;}
 function burn(address from,uint value) external {balanceOf[from]-=value;}
 function transfer(address to,uint value) external returns(bool){balanceOf[msg.sender]-=value;balanceOf[to]+=value;return mode!=1;}
 function transferFrom(address from,address to,uint value) external returns(bool){balanceOf[from]-=value;balanceOf[to]+=value;return mode!=1;}
}
contract RHBranch {
 uint public unbacked=6000e18;uint public price=2000e18;bool public redeemable=true;
 uint public lastZombieTroveId;uint public calls;uint public priceCalls;uint public entire=9000e18;
 uint public failure;
 function setFailure(uint mode) external {failure=mode;}
 function fail() internal view {if(failure==1)revert("oracle");if(failure==2)assembly{mstore(0,1) return(0,31)}}
 uint public troveDebt=3000e18;uint public troveColl=10e18;
 function config(uint u,uint p,bool active,uint z,uint debt,uint coll) external {unbacked=u;price=p;redeemable=active;lastZombieTroveId=z;troveDebt=debt;troveColl=coll;}
 function troveManager() external view returns(address){return address(this);}
 function sortedTroves() external view returns(address){return address(this);}
 function priceFeed() external view returns(address){return address(this);}
 function getUnbackedPortionPriceAndRedeemability() external returns(uint,uint,bool){calls++;fail();return(unbacked,price,redeemable);}
 function fetchRedemptionPrice() external returns(uint,bool){priceCalls++;fail();return(price,false);}
 function getEntireBranchDebt() external view returns(uint){return entire;}
 function getLast() external pure returns(uint){return 3;}
 function getPrev(uint id) external pure returns(uint){return id>1?id-1:0;}
 function getLatestTroveData(uint id) external view returns(LatestTroveData memory t){t.entireDebt=troveDebt;t.entireColl=id==2?troveColl/100:troveColl;}
}
contract RHRegistry {
 RHToken public boldToken=new RHToken();
 RHBranch[] public branches;RHToken[] public tokens;
 uint public fee=5e15;
 constructor(){for(uint i;i<3;i++){branches.push(new RHBranch());tokens.push(new RHToken());}}
 function totalCollaterals() external view returns(uint){return branches.length;}
 function getTroveManager(uint index) external view returns(address){return address(branches[index]);}
 function getToken(uint index) external view returns(address){return address(tokens[index]);}
 function getRedemptionRateForRedeemedAmount(uint amount) external view returns(uint){return fee+amount/100000;}
 function redeemCollateral(uint amount,uint,uint maxFee) external {
   require(maxFee>=fee,"fee");boldToken.burn(msg.sender,amount*3/4);
   for(uint i;i<tokens.length;i++)tokens[i].mint(msg.sender,(i+1)*1e18);
 }
 function addresses() external view returns(IAddressesRegistry[] memory a){a=new IAddressesRegistry[](branches.length);for(uint i;i<a.length;i++)a[i]=IAddressesRegistry(address(branches[i]));}
}
contract RedemptionHelperParityTest {
 RHVm constant vm=RHVm(address(uint160(uint(keccak256("hevm cheat code")))));
 RHRegistry registry;RedemptionHelper actual;RedemptionHelper expected;
 function feCode() internal view returns(bytes memory){return vm.parseBytes(vm.readFile("build/RedemptionHelper.bin"));}
 function deploy(bytes memory init) internal returns(address a){assembly{a:=create(0,add(init,32),mload(init))}require(a.code.length>0&&a.code.length<=24576,"deployment");}
 function setUp() public {registry=new RHRegistry();actual=RedemptionHelper(deploy(bytes.concat(feCode(),abi.encode(registry,registry.addresses()))));expected=new RedemptionHelper(ICollateralRegistry(address(registry)),registry.addresses());}
 function compare(bytes memory data) internal returns(bool){
   uint[6] memory beforeCalls;uint[6] memory afterCalls;
   for(uint i;i<3;i++){beforeCalls[i*2]=registry.branches(i).calls();beforeCalls[i*2+1]=registry.branches(i).priceCalls();}
   (bool ok,bytes memory a)=address(actual).call(data);
   for(uint i;i<3;i++){afterCalls[i*2]=registry.branches(i).calls();afterCalls[i*2+1]=registry.branches(i).priceCalls();}
   (bool success,bytes memory b)=address(expected).call(data);
   for(uint i;i<3;i++){require(afterCalls[i*2]-beforeCalls[i*2]==registry.branches(i).calls()-afterCalls[i*2],"manager calls");require(afterCalls[i*2+1]-beforeCalls[i*2+1]==registry.branches(i).priceCalls()-afterCalls[i*2+1],"price calls");}
   require(ok==success,"success");require(keccak256(a)==keccak256(b),"return/revert");return ok;
 }
 function tryDeploy(bytes memory init) internal returns(bool ok,bytes memory result){
  address a;assembly{a:=create(0,add(init,32),mload(init)) let n:=returndatasize() result:=mload(0x40) mstore(result,n) returndatacopy(add(result,32),0,n) mstore(0x40,add(add(result,32),n))}return(a!=address(0),result);
 }
 function constructorFailure(bytes memory args) internal {
  (bool ok,bytes memory a)=tryDeploy(bytes.concat(feCode(),args));
  (bool success,bytes memory b)=tryDeploy(bytes.concat(type(RedemptionHelper).creationCode,args));
  require(!ok&&!success,"constructor success");require(keccak256(a)==keccak256(b),"constructor revert");
 }
 function testConstructorFailuresAndMalformedArrays() public {
  constructorFailure(abi.encode(registry,new address[](2)));
  address[] memory branches=new address[](3);for(uint i;i<3;i++)branches[i]=address(registry.branches(0));
  constructorFailure(abi.encode(registry,branches));
  constructorFailure(abi.encode(address(registry),uint(64),type(uint).max));
  constructorFailure(abi.encode(address(registry),uint(64),uint(3),type(uint).max,uint(0),uint(0)));
  constructorFailure(abi.encode(address(registry),uint(64),uint(3)));
 }
 function testMemoryArrayDecoderAndMalformedCall() public {
  bytes4 selector=actual.redeemCollateral.selector;
  compare(abi.encodePacked(selector,abi.encode(uint(1),uint(0),uint(1e18),uint(128),type(uint).max)));
  compare(abi.encodePacked(selector,abi.encode(uint(1),uint(0),uint(1e18),uint(128),uint(3))));
  compare(abi.encodePacked(selector,abi.encode(uint(1),uint(0),uint(1e18),type(uint).max)));
 }
 function testConstructorGettersAndStorage() public {
  require(compare(abi.encodeCall(actual.numBranches,())));require(compare(abi.encodeCall(actual.collateralRegistry,())));require(compare(abi.encodeCall(actual.boldToken,())));
  require(vm.load(address(actual),0)==vm.load(address(expected),0));
  for(uint i;i<3;i++){require(compare(abi.encodeCall(actual.addresses,(i))));bytes32 slot=bytes32(uint(keccak256(abi.encode(uint(0))))+i);require(vm.load(address(actual),slot)==vm.load(address(expected),slot));}
  require(!compare(abi.encodeCall(actual.addresses,(3))));
 }
 function testSimulationLimitsZombieAndFallback() public {
  registry.branches(1).config(3000e18,1500e18,true,4,3000e18,10e18);
  registry.branches(2).config(1000e18,1000e18,false,0,3000e18,10e18);
  for(uint limit;limit<6;limit++){
   require(compare(abi.encodeCall(actual.simulateRedemption,(15000e18,limit))));
   require(compare(abi.encodeCall(actual.truncateRedemption,(15000e18,limit))));
  }
  for(uint i;i<3;i++)registry.branches(i).config(0,2000e18,true,0,3000e18,10e18);
  require(compare(abi.encodeCall(actual.simulateRedemption,(30000e18,0))));
  require(compare(abi.encodeCall(actual.truncateRedemption,(30000e18,1))));
  for(uint i;i<3;i++)registry.branches(i).config(0,2000e18,false,0,3000e18,10e18);
  require(compare(abi.encodeCall(actual.truncateRedemption,(30000e18,1))));
 }
 function testExternalFailureMalformedReturnsAndRollback() public {
  for(uint mode=1;mode<=2;mode++){
   registry.branches(1).setFailure(mode);
   require(!compare(abi.encodeCall(actual.simulateRedemption,(1000e18,0))));
   require(!compare(abi.encodeCall(actual.truncateRedemption,(1000e18,0))));
   require(registry.branches(0).calls()==0,"external rollback");
  }
 }
 function testZeroAmountAndArithmeticFailures() public {
  require(compare(abi.encodeCall(actual.simulateRedemption,(0,0))));
  require(compare(abi.encodeCall(actual.truncateRedemption,(0,0))));
  registry.branches(0).config(6000e18,2000e18,true,0,0,10e18);
  require(!compare(abi.encodeCall(actual.simulateRedemption,(1000e18,0))));
  registry.branches(0).config(type(uint).max,2000e18,true,0,3000e18,10e18);
  require(!compare(abi.encodeCall(actual.simulateRedemption,(type(uint).max,0))));
 }
 function testRedemptionTransfersRefundAndSlippageRollback() public {
  RHToken bold=registry.boldToken();bold.mint(address(this),2000e18);bold.mint(address(actual),123);bold.mint(address(expected),123);
  for(uint i;i<3;i++){registry.tokens(i).mint(address(actual),777);registry.tokens(i).mint(address(expected),777);}
  uint[] memory minimum=new uint[](3);minimum[0]=1e18;minimum[1]=2e18;minimum[2]=3e18;
  require(compare(abi.encodeCall(actual.redeemCollateral,(1000e18,1,1e18,minimum))));
  require(bold.balanceOf(address(actual))==123&&bold.balanceOf(address(expected))==123);require(bold.balanceOf(address(this))==500e18);
  for(uint i;i<3;i++){require(registry.tokens(i).balanceOf(address(actual))==777&&registry.tokens(i).balanceOf(address(expected))==777);require(registry.tokens(i).balanceOf(address(this))==2*(i+1)*1e18);}
  minimum[2]++;bold.mint(address(this),2000e18);
  require(!compare(abi.encodeCall(actual.redeemCollateral,(1000e18,1,1e18,minimum))));
  require(bold.balanceOf(address(this))==2500e18);require(bold.balanceOf(address(actual))==123);
  require(!compare(abi.encodeCall(actual.redeemCollateral,(0,1,1e18,minimum))));
  require(!compare(abi.encodeCall(actual.redeemCollateral,(1000e18,1,1e18,new uint[](2)))));
 }
 function testFalseBoldReturnAndFailedCollateralReturn() public {
  registry.boldToken().setMode(1);registry.boldToken().mint(address(this),2000e18);
  require(compare(abi.encodeCall(actual.redeemCollateral,(1000e18,1,1e18,new uint[](3)))));
  registry.boldToken().mint(address(this),2000e18);registry.tokens(2).setMode(1);
  require(!compare(abi.encodeCall(actual.redeemCollateral,(1000e18,1,1e18,new uint[](3)))));
 }
 function testFuzzSimulation(uint96 amount,uint96 debt,uint8 limit,bool active,bool zombie) public {
  registry.branches(0).config(uint(debt),2000e18,active,zombie?4:0,3000e18,10e18);
  compare(abi.encodeCall(actual.simulateRedemption,(uint(amount),uint(limit)%6)));
  compare(abi.encodeCall(actual.truncateRedemption,(uint(amount),uint(limit)%6)));
 }
}
