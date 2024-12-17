// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Settings} from "src/core/Settings.sol";
import {ReflectMath} from "src/core/ReflectMath.sol";

import {BasisPoints, BASIS} from "src/types/BasisPoints.sol";
import {Shares} from "src/types/Shares.sol";
import {Tokens} from "src/types/Tokens.sol";
import {TokensXShares, tmp, alloc, SharesToTokens} from "src/types/TokensXShares.sol";
import {TokensXBasisPoints, scale, castUp} from "src/types/TokensXBasisPoints.sol";

import {UnsafeMath} from "src/lib/UnsafeMath.sol";

import {Test} from "@forge-std/Test.sol";
import {Boilerplate} from "./Boilerplate.sol";

import {console} from "@forge-std/console.sol";

contract ReflectMathTest is Boilerplate, Test {
    using UnsafeMath for uint256;
    using SharesToTokens for Shares;

    function _boundCommon(Tokens totalSupply, Shares totalShares, Shares fromShares, uint256 sharesRatio)
        internal
        pure
        returns (Tokens, Shares, Shares, Tokens)
    {
        totalSupply = Tokens.wrap(
            bound(Tokens.unwrap(totalSupply), 10 ** Settings.DECIMALS + 1 wei, Tokens.unwrap(Settings.INITIAL_SUPPLY))
        );
        //sharesRatio = bound(sharesRatio, Settings.MIN_SHARES_RATIO, Settings.INITIAL_SHARES_RATIO);
        sharesRatio = Settings.MIN_SHARES_RATIO; // TODO: remove
        Shares maxShares = Shares.wrap(Tokens.unwrap(totalSupply) * (sharesRatio + 1) - 1 wei);
        maxShares = maxShares > Settings.INITIAL_SHARES ? Settings.INITIAL_SHARES : maxShares;
        totalShares = Shares.wrap(
            bound(Shares.unwrap(totalShares), Tokens.unwrap(totalSupply) * sharesRatio, Shares.unwrap(maxShares))
        );

        fromShares = Shares.wrap(
            bound(
                Shares.unwrap(fromShares),
                Shares.unwrap(totalShares).unsafeDivUp(Tokens.unwrap(totalSupply)),
                Shares.unwrap(totalShares.div(Settings.ANTI_WHALE_DIVISOR)) - 1
            )
        );

        Tokens fromBalance = fromShares.toTokens(totalSupply, totalShares);
        assertGt(Tokens.unwrap(fromBalance), 0);
        return (totalSupply, totalShares, fromShares, fromBalance);
    }

    function _boundCommon(Tokens totalSupply, Shares totalShares, Shares fromShares, Tokens amount, uint256 sharesRatio)
        internal
        pure
        returns (Tokens, Shares, Shares, Tokens, Tokens)
    {
        Tokens fromBalance;
        (totalSupply, totalShares, fromShares, fromBalance) =
            _boundCommon(totalSupply, totalShares, fromShares, sharesRatio);
        assume(Tokens.unwrap(fromBalance) > 1 wei);
        amount = Tokens.wrap(bound(Tokens.unwrap(amount), 1 wei, Tokens.unwrap(fromBalance) - 1 wei));
        return (totalSupply, totalShares, fromShares, fromBalance, amount);
    }

    function testTransferSome(
        Tokens totalSupply,
        Shares totalShares,
        Shares fromShares,
        Shares toShares,
        Tokens amount,
        BasisPoints taxRate/*,
        uint256 sharesRatio*/
    ) public view virtual {
        Tokens fromBalance;
        (totalSupply, totalShares, fromShares, fromBalance, amount) =
            _boundCommon(totalSupply, totalShares, fromShares, amount, /* sharesRatio */ 0);

        taxRate = BasisPoints.wrap(
            uint16(
                bound(
                    BasisPoints.unwrap(taxRate),
                    BasisPoints.unwrap(Settings.MIN_TAX),
                    BasisPoints.unwrap(Settings.MAX_TAX)
                )
            )
        );

        toShares =
            Shares.wrap(bound(Shares.unwrap(toShares), 0, Shares.unwrap(totalShares.div(Settings.ANTI_WHALE_DIVISOR))));
        Tokens toBalance = toShares.toTokens(totalSupply, totalShares);

        //console.log("===");
        //console.log("totalSupply", Tokens.unwrap(totalSupply));
        //console.log("taxRate    ", BasisPoints.unwrap(taxRate));
        //console.log("amount     ", Tokens.unwrap(amount));
        //console.log("===");
        //console.log("fromBalance", Tokens.unwrap(fromBalance));
        //console.log("toBalance  ", Tokens.unwrap(toBalance));
        //console.log("===");
        (Shares newFromShares, Shares newToShares, Shares newTotalShares) =
            ReflectMath.getTransferShares(amount, taxRate, totalSupply, totalShares, fromShares, toShares);
        assertLe(Shares.unwrap(newFromShares), Shares.unwrap(fromShares), "from shares increased");
        assertGe(Shares.unwrap(newToShares), Shares.unwrap(toShares), "to shares decreased");
        assertLe(Shares.unwrap(newTotalShares), Shares.unwrap(totalShares), "total shares increased");
        assertEq(
            Shares.unwrap(totalShares - newTotalShares),
            Shares.unwrap(fromShares + toShares - (newFromShares + newToShares)),
            "shares delta"
        );

        Tokens newFromBalance = newFromShares.toTokens(totalSupply, newTotalShares);
        Tokens newToBalance = newToShares.toTokens(totalSupply, newTotalShares);
        Tokens expectedNewFromBalance = fromBalance - amount;
        Tokens expectedNewToBalanceHi = toBalance + castUp(scale(amount, BASIS - taxRate));
        Tokens expectedNewToBalanceLo = toBalance + amount - castUp(scale(amount, taxRate));

        assertEq(Tokens.unwrap(newFromBalance), Tokens.unwrap(expectedNewFromBalance), "newFromBalance");
        // TODO: tighten these bounds to exact equality
        assertGe(Tokens.unwrap(newToBalance), Tokens.unwrap(expectedNewToBalanceLo), "newToBalance lower");
        assertLe(Tokens.unwrap(newToBalance), Tokens.unwrap(expectedNewToBalanceHi), "newToBalance upper");
    }

    function testTransferAll(
        Tokens totalSupply,
        Shares totalShares,
        Shares fromShares,
        Shares toShares,
        BasisPoints taxRate/*,
        uint256 sharesRatio*/
    ) public pure virtual {
        Tokens fromBalance;
        (totalSupply, totalShares, fromShares, fromBalance) =
            _boundCommon(totalSupply, totalShares, fromShares, /* sharesRatio */ 0);
        taxRate = BasisPoints.wrap(
            uint16(
                bound(
                    BasisPoints.unwrap(taxRate),
                    BasisPoints.unwrap(Settings.MIN_TAX),
                    BasisPoints.unwrap(Settings.MAX_TAX)
                )
            )
        );

        toShares =
            Shares.wrap(bound(Shares.unwrap(toShares), 0, Shares.unwrap(totalShares.div(Settings.ANTI_WHALE_DIVISOR))));
        Tokens toBalance = toShares.toTokens(totalSupply, totalShares);

        (Shares newToShares, Shares newTotalShares) =
            ReflectMath.getTransferShares(taxRate, totalSupply, totalShares, fromShares, toShares);

        assertGe(Shares.unwrap(newToShares), Shares.unwrap(toShares), "to shares decreased");
        assertLe(Shares.unwrap(newTotalShares), Shares.unwrap(totalShares), "total shares increased");
        assertEq(
            Shares.unwrap(totalShares - newTotalShares),
            Shares.unwrap(fromShares + toShares - newToShares),
            "shares delta"
        );

        Tokens newToBalance = newToShares.toTokens(totalSupply, newTotalShares);
        //console.log("      newToShares", Shares.unwrap(newToShares));
        //console.log("         toShares", Shares.unwrap(toShares));

        // TODO: tighter bounds
        Tokens expectedNewToBalanceLo = toBalance + fromBalance - castUp(scale(fromBalance, taxRate));
        Tokens expectedNewToBalanceHi = toBalance + castUp(scale(fromBalance, BASIS - taxRate));
        //assertEq(Tokens.unwrap(newToBalance), Tokens.unwrap(expectedNewToBalanceLo), "newToBalance");
        if (newToShares == toShares) {
            assertGe(Tokens.unwrap(newToBalance), Tokens.unwrap(expectedNewToBalanceLo), "newToBalance lower");
            assertLe(Tokens.unwrap(newToBalance), Tokens.unwrap(expectedNewToBalanceHi), "newToBalance upper");
        } else {
            assertEq(Tokens.unwrap(newToBalance), Tokens.unwrap(expectedNewToBalanceLo), "newToBalance");
        }
    }

    function testTransferSomePair(
        Tokens totalSupply,
        Shares totalShares,
        Shares toShares,
        Tokens amount,
        BasisPoints taxRate/*,
        uint256 sharesRatio*/
    ) public view virtual {
        Tokens toBalance;
        (totalSupply, totalShares, toShares, toBalance) =
            _boundCommon(totalSupply, totalShares, toShares, /* sharesRatio */ 0);
        amount = Tokens.wrap(bound(Tokens.unwrap(amount), 1 wei, Tokens.unwrap(totalSupply.div(Settings.ANTI_WHALE_DIVISOR)) - 1 wei));

        taxRate = BasisPoints.wrap(
            uint16(
                bound(
                    BasisPoints.unwrap(taxRate),
                    BasisPoints.unwrap(Settings.MIN_TAX),
                    BasisPoints.unwrap(Settings.MAX_TAX)
                )
            )
        );

        (Shares newToShares, Tokens newTotalSupply, Shares newTotalShares) = ReflectMath.getTransferShares(taxRate, totalSupply, totalShares, amount, toShares);

        assertGe(Shares.unwrap(newToShares), Shares.unwrap(toShares), "to shares decreased");
        assertGe(Shares.unwrap(newTotalShares), Shares.unwrap(totalShares), "total shares decreased");
        assertEq(
            Shares.unwrap(newTotalShares - totalShares),
            Shares.unwrap(newToShares - toShares),
            "shares delta"
        );

        Tokens newToBalance = newToShares.toTokens(newTotalSupply, newTotalShares);

        // TODO: tighter bounds
        Tokens expectedNewToBalanceLo = toBalance + amount - castUp(scale(amount, taxRate));
        Tokens expectedNewToBalanceHi = toBalance + castUp(scale(amount, BASIS - taxRate));
        //if (newToShares == toShares) {
            assertGe(Tokens.unwrap(newToBalance), Tokens.unwrap(expectedNewToBalanceLo), "newToBalance lower");
            assertLe(Tokens.unwrap(newToBalance), Tokens.unwrap(expectedNewToBalanceHi), "newToBalance upper");
        /*
        } else {
            assertEq(Tokens.unwrap(newToBalance), Tokens.unwrap(expectedNewToBalanceLo), "newToBalance");
        }
        */
    }

    function testDeliver(
        Tokens totalSupply,
        Shares totalShares,
        Shares fromShares,
        Tokens amount/*,
        uint256 sharesRatio*/
    ) public view virtual {
        Tokens fromBalance;
        (totalSupply, totalShares, fromShares, fromBalance, amount) =
            _boundCommon(totalSupply, totalShares, fromShares, amount, /* sharesRatio */ 0);
        assume(fromShares < totalShares.div(2));

        (Shares newFromShares, Shares newTotalShares) =
            ReflectMath.getDeliverShares(amount, totalSupply, totalShares, fromShares);
        assertLe(Shares.unwrap(newFromShares), Shares.unwrap(fromShares));
        assertLe(Shares.unwrap(newTotalShares), Shares.unwrap(totalShares));

        Tokens newFromBalance = newFromShares.toTokens(totalSupply, newTotalShares);
        Tokens expectedNewFromBalance = fromBalance - amount;

        assertEq(
            Tokens.unwrap(newFromBalance), Tokens.unwrap(expectedNewFromBalance), "new balance, expected new balance"
        );
    }
}
