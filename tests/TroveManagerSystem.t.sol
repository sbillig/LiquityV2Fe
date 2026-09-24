// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
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
interface TMSystemVm {function envOr(string calldata,string calldata) external returns(string memory);}
contract ManagerSystemCollateral is ActiveCollateralToken {
    function name() external pure returns(string memory){return "Collateral";}
    function symbol() external pure returns(string memory){return "COLL";}
}
contract ManagerSystemPrice {
    uint public price=2000e18;
    function set(uint value) external {price=value;}
    function fetchPrice() external view returns(uint,bool){return(price,false);}
    function fetchRedemptionPrice() external view returns(uint,bool){return(price,false);}
}
contract TroveManagerSystemTest {
    PoolVm constant vm=PoolVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address constant ALICE=address(0xa11ce);address constant BOB=address(0xb0b);address constant ROUTER=address(0x100);
    struct System {
        AddressesRegistry registry;ActivePool active;DefaultPool defaults;StabilityPool sp;BoldToken bold;ManagerSystemCollateral coll;
        TroveManager manager;TroveNFT nft;SortedTroves sorted;CollSurplusPool surplus;address gasPool;ManagerSystemPrice feed;
    }
    function code(string memory name,bool fe) internal returns(bytes memory){
        if(fe)return vm.parseBytes(vm.readFile(string.concat(TMSystemVm(address(vm)).envOr("LIQUITY_TEST_ARTIFACTS","build"),"/",name,".bin")));
        bytes32 k=keccak256(bytes(name));
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
    function make(bool fe) internal returns(System memory s){
        s.coll=new ManagerSystemCollateral();s.feed=new ManagerSystemPrice();
        s.registry=AddressesRegistry(deploy(bytes.concat(code("AddressesRegistry",fe),abi.encode(address(this),15e17,11e17,1e17,11e17,5e16,1e17))));
        s.bold=BoldToken(deploy(bytes.concat(code("BoldToken",fe),abi.encode(address(this)))));
        bytes[8] memory init;
        init[0]=bytes.concat(code("ActivePool",fe),abi.encode(s.registry));init[1]=bytes.concat(code("DefaultPool",fe),abi.encode(s.registry));init[2]=bytes.concat(code("StabilityPool",fe),abi.encode(s.registry));
        bytes[3] memory modules;
        if(fe){modules[0]=code("TroveOperations",true);modules[1]=code("TroveRedemptions",true);modules[2]=bytes.concat(code("TroveLiquidations",true),abi.encode(s.registry));
            init[3]=bytes.concat(code("TroveManager",true),abi.encode(s.registry,predict(modules[0]),predict(modules[1]),predict(modules[2])));
        }else init[3]=bytes.concat(code("TroveManager",false),abi.encode(s.registry));
        init[4]=bytes.concat(code("TroveNFT",fe),abi.encode(s.registry));init[5]=bytes.concat(code("SortedTroves",fe),abi.encode(s.registry));init[6]=bytes.concat(code("GasPool",fe),abi.encode(s.registry));init[7]=bytes.concat(code("CollSurplusPool",fe),abi.encode(s.registry));
        address[18] memory vars;vars[0]=address(s.coll);vars[1]=address(this);vars[2]=predict(init[3]);vars[3]=predict(init[4]);vars[5]=predict(init[2]);vars[6]=address(s.feed);vars[7]=predict(init[0]);vars[8]=predict(init[1]);vars[9]=predict(init[6]);vars[10]=predict(init[7]);vars[11]=predict(init[5]);vars[12]=ROUTER;vars[15]=address(this);vars[16]=address(s.bold);vars[17]=address(s.coll);
        (bool ok,)=address(s.registry).call(abi.encodePacked(AddressesRegistry.setAddresses.selector,abi.encode(vars)));require(ok);
        if(fe){deploy(modules[0]);deploy(modules[1]);deploy(modules[2]);}
        s.active=ActivePool(deploy(init[0]));s.defaults=DefaultPool(deploy(init[1]));s.sp=StabilityPool(deploy(init[2]));s.manager=TroveManager(deploy(init[3]));s.nft=TroveNFT(deploy(init[4]));s.sorted=SortedTroves(deploy(init[5]));s.gasPool=deploy(init[6]);s.surplus=CollSurplusPool(deploy(init[7]));
        s.bold.setBranchAddresses(address(s.manager),address(s.sp),address(this),address(s.active));s.bold.setCollateralRegistry(address(this));
    }
    function onLiquidateTrove(uint256) external {}
    function open(System memory s,uint id,address owner,uint coll,uint rate) internal {
        TroveChange memory c;c.debtIncrease=3000e18;c.collIncrease=coll;c.newWeightedRecordedDebt=3000e18*rate;
        s.manager.onOpenTrove(owner,id,c,rate);s.sorted.insert(id,rate,0,0);
        s.active.mintAggInterestAndAccountForTroveChange(c,address(0));s.bold.mint(owner,3000e18);
        s.coll.mint(address(this),coll);s.active.receiveColl(coll);s.coll.mint(s.gasPool,375e14);
    }
    function conserve(System memory s) internal view {
        require(s.bold.balanceOf(address(s.sp))==s.sp.getTotalBoldDeposits()+s.sp.getYieldGainsOwed()+s.sp.getYieldGainsPending(),"BOLD conservation");
        require(s.coll.balanceOf(address(s.active))==s.active.getCollBalance(),"active collateral");
        require(s.coll.balanceOf(address(s.defaults))==s.defaults.getCollBalance(),"default collateral");
        require(s.coll.balanceOf(address(s.sp))==s.sp.getCollBalance(),"SP collateral");
    }
    function run(System memory s) internal returns(bytes32){
        s.coll.approve(address(s.active),type(uint).max);open(s,1,ALICE,20e18,5e16);open(s,2,BOB,10e18,6e16);open(s,3,ALICE,30e18,7e16);
        vm.prank(ALICE);s.sp.provideToSP(1500e18,false);TimeVm(address(vm)).warp(block.timestamp+365 days);
        s.feed.set(300e18);uint[] memory ids=new uint[](1);ids[0]=2;s.manager.batchLiquidateTroves(ids);
        require(uint(s.manager.getTroveStatus(2))==3&&!s.sorted.contains(2)&&s.nft.balanceOf(BOB)==0);conserve(s);
        uint redeemed=s.manager.redeemCollateral(ALICE,1000e18,300e18,5e15,0);s.bold.burn(ALICE,redeemed);require(redeemed==1000e18);conserve(s);
        s.manager.shutdown();ids=new uint[](2);ids[0]=3;ids[1]=1;vm.prank(ALICE);s.manager.urgentRedemption(2000e18,ids,0);conserve(s);
        vm.prank(ALICE);s.sp.withdrawFromSP(0,true);conserve(s);
        LatestTroveData memory one=s.manager.getLatestTroveData(1);LatestTroveData memory three=s.manager.getLatestTroveData(3);
        bytes32 pools=keccak256(abi.encode(s.active.getCollBalance(),s.active.getBoldDebt(),s.defaults.getCollBalance(),s.defaults.getBoldDebt(),s.sp.getTotalBoldDeposits(),s.sp.getCollBalance(),s.sp.getYieldGainsOwed(),s.sp.getYieldGainsPending()));
        bytes32 balances=keccak256(abi.encode(s.bold.totalSupply(),s.bold.balanceOf(ALICE),s.bold.balanceOf(BOB),s.bold.balanceOf(ROUTER),s.coll.balanceOf(ALICE),s.coll.balanceOf(address(this)),s.coll.balanceOf(s.gasPool)));
        return keccak256(abi.encode(one,three,pools,balances,s.sorted.getSize(),s.manager.getTroveIdsCount()));
    }
    function testActualManagerLiquidationRedemptionAndShutdown() public {
        TimeVm(address(vm)).warp(1000);bytes32 actual=run(make(true));
        TimeVm(address(vm)).warp(1000);bytes32 expected=run(make(false));require(actual==expected,"connected manager parity");
    }
}
