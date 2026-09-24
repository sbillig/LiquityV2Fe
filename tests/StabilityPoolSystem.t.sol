// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {AddressesRegistry} from "../reference/bold/contracts/src/AddressesRegistry.sol";
import {ActivePool} from "../reference/bold/contracts/src/ActivePool.sol";
import {DefaultPool} from "../reference/bold/contracts/src/DefaultPool.sol";
import {StabilityPool} from "../reference/bold/contracts/src/StabilityPool.sol";
import {BoldToken} from "../reference/bold/contracts/src/BoldToken.sol";
import {TroveChange} from "../reference/bold/contracts/src/Types/TroveChange.sol";
import {ActiveCollateralToken,TimeVm} from "./ActivePoolParity.t.sol";
import {PoolVm} from "./DefaultPoolParity.t.sol";
interface SPSystemVm {function envOr(string calldata,string calldata) external returns(string memory);}
contract StabilityPoolSystemTest {
    PoolVm constant vm=PoolVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address constant ALICE=address(0xa11ce);address constant BOB=address(0xb0b);address constant ROUTER=address(0x100);
    struct System {AddressesRegistry registry;ActivePool active;DefaultPool defaults;StabilityPool sp;BoldToken bold;ActiveCollateralToken coll;}
    function code(string memory name,bool fe) internal returns(bytes memory){
        if(fe)return vm.parseBytes(vm.readFile(string.concat(SPSystemVm(address(vm)).envOr("LIQUITY_TEST_ARTIFACTS","build"),"/",name,".bin")));
        bytes32 key=keccak256(bytes(name));
        if(key==keccak256("AddressesRegistry"))return type(AddressesRegistry).creationCode;
        if(key==keccak256("ActivePool"))return type(ActivePool).creationCode;
        if(key==keccak256("DefaultPool"))return type(DefaultPool).creationCode;
        if(key==keccak256("StabilityPool"))return type(StabilityPool).creationCode;
        if(key==keccak256("BoldToken"))return type(BoldToken).creationCode;
        revert("unknown contract");
    }
    function predict(bytes memory init) internal view returns(address){return address(uint160(uint256(keccak256(abi.encodePacked(hex"ff",address(this),bytes32(0),keccak256(init))))));}
    function deploy(bytes memory init) internal returns(address target){require(init.length<=49152,"initcode");assembly{target:=create2(0,add(init,32),mload(init),0)}require(target.code.length>0&&target.code.length<=24576,"deploy");}
    function make(bool fe) internal returns(System memory s){
        s.coll=new ActiveCollateralToken();
        s.registry=AddressesRegistry(deploy(bytes.concat(code("AddressesRegistry",fe),abi.encode(address(this),15e17,11e17,1e17,11e17,5e16,1e17))));
        s.bold=BoldToken(deploy(bytes.concat(code("BoldToken",fe),abi.encode(address(this)))));
        bytes memory activeInit=bytes.concat(code("ActivePool",fe),abi.encode(s.registry));bytes memory defaultInit=bytes.concat(code("DefaultPool",fe),abi.encode(s.registry));bytes memory spInit=bytes.concat(code("StabilityPool",fe),abi.encode(s.registry));
        address[18] memory vars;vars[0]=address(s.coll);vars[1]=address(this);vars[2]=address(this);vars[5]=predict(spInit);vars[7]=predict(activeInit);vars[8]=predict(defaultInit);vars[12]=ROUTER;vars[15]=address(this);vars[16]=address(s.bold);vars[17]=address(s.coll);
        (bool ok,)=address(s.registry).call(abi.encodePacked(AddressesRegistry.setAddresses.selector,abi.encode(vars)));require(ok);
        s.active=ActivePool(deploy(activeInit));s.defaults=DefaultPool(deploy(defaultInit));s.sp=StabilityPool(deploy(spInit));
        s.bold.setBranchAddresses(address(this),address(s.sp),address(this),address(s.active));s.bold.setCollateralRegistry(address(this));
    }
    function conservation(System memory s) internal view {
        require(s.bold.balanceOf(address(s.sp))==s.sp.getTotalBoldDeposits()+s.sp.getYieldGainsOwed()+s.sp.getYieldGainsPending(),"SP BOLD conservation");
        require(s.coll.balanceOf(address(s.sp))==s.sp.getCollBalance(),"SP collateral conservation");
        require(s.coll.balanceOf(address(s.active))==s.active.getCollBalance(),"active collateral conservation");
    }
    function run(System memory s) internal returns(uint256[20] memory result){
        s.coll.mint(address(this),100e18);s.coll.approve(address(s.active),type(uint256).max);s.active.receiveColl(100e18);
        TroveChange memory change;change.debtIncrease=2000e18;change.newWeightedRecordedDebt=2000e18*5e16;change.upfrontFee=7e18;
        s.active.mintAggInterestAndAccountForTroveChange(change,address(0));s.bold.mint(ALICE,1500e18);s.bold.mint(BOB,500e18);
        require(s.sp.getYieldGainsPending()==525e16);conservation(s);
        vm.prank(ALICE);s.sp.provideToSP(1000e18,false);vm.prank(BOB);s.sp.provideToSP(500e18,false);
        require(s.sp.getDepositorYieldGain(ALICE)==525e16&&s.sp.getDepositorYieldGain(BOB)==0);conservation(s);
        TimeVm(address(vm)).warp(block.timestamp+365 days);
        require(s.sp.getDepositorYieldGainWithPending(ALICE)==5525e16&&s.sp.getDepositorYieldGainWithPending(BOB)==25e18);
        vm.prank(ALICE);s.sp.withdrawFromSP(0,false);vm.prank(BOB);s.sp.withdrawFromSP(0,true);
        require(s.sp.deposits(ALICE)==105525e16&&s.sp.getTotalBoldDeposits()==155525e16);conservation(s);
        // Drive the manager's pool-side liquidation accounting with actual Fe pools.
        change.debtIncrease=0;change.debtDecrease=200e18;change.upfrontFee=0;change.oldWeightedRecordedDebt=2000e18*5e16;change.newWeightedRecordedDebt=1800e18*5e16;
        s.active.mintAggInterestAndAccountForTroveChange(change,address(0));
        s.sp.offset(200e18,10e18);
        require(s.active.aggRecordedDebt()==1907e18&&s.bold.totalSupply()==1907e18);conservation(s);
        vm.prank(ALICE);s.sp.withdrawFromSP(0,true);vm.prank(BOB);s.sp.withdrawFromSP(0,false);
        require(s.sp.stashedColl(BOB)>0);conservation(s);
        TimeVm(address(vm)).warp(block.timestamp+30 days);vm.prank(BOB);s.sp.withdrawFromSP(0,true);conservation(s);
        result=[s.active.getCollBalance(),s.active.getBoldDebt(),s.active.aggRecordedDebt(),s.bold.totalSupply(),s.bold.balanceOf(ALICE),s.bold.balanceOf(BOB),s.bold.balanceOf(ROUTER),s.bold.balanceOf(address(s.sp)),s.sp.getTotalBoldDeposits(),s.sp.getYieldGainsOwed(),s.sp.getYieldGainsPending(),s.sp.getCollBalance(),s.sp.getCompoundedBoldDeposit(ALICE),s.sp.getCompoundedBoldDeposit(BOB),s.sp.getDepositorYieldGain(ALICE),s.sp.stashedColl(BOB),s.coll.balanceOf(ALICE),s.coll.balanceOf(BOB),s.sp.P(),s.sp.currentScale()];
    }
    function testActualPoolsInterestOffsetAndClaims() public {
        TimeVm(address(vm)).warp(1000);System memory first=make(true);uint256[20] memory actual=run(first);
        TimeVm(address(vm)).warp(1000);System memory second=make(false);uint256[20] memory expected=run(second);
        require(keccak256(abi.encode(actual))==keccak256(abi.encode(expected)),"connected state parity");
    }
}
