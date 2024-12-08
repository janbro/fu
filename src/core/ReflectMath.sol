// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BasisPoints, BASIS} from "../types/BasisPoints.sol";
import {Shares} from "../types/Shares.sol";
import {Tokens} from "../types/Tokens.sol";
import {scale} from "../types/SharesXBasisPoints.sol";
import {scale, castUp} from "../types/TokensXBasisPoints.sol";
import {TokensXShares, tmp, alloc, SharesToTokens} from "../types/TokensXShares.sol";
import {TokensXShares2, tmp as tmp2, alloc as alloc2} from "../types/TokensXShares2.sol";
import {TokensXBasisPointsXShares, tmp as tmp3, alloc as alloc3} from "../types/TokensXBasisPointsXShares.sol";
import {TokensXBasisPointsXShares2, tmp as tmp4, alloc as alloc4} from "../types/TokensXBasisPointsXShares2.sol";
import {SharesXBasisPoints} from "../types/SharesXBasisPoints.sol";
import {Shares2XBasisPoints, tmp as tmp5, alloc as alloc5} from "../types/Shares2XBasisPoints.sol";

import {UnsafeMath} from "../lib/UnsafeMath.sol";

import {console} from "@forge-std/console.sol";

library ReflectMath {
    using UnsafeMath for uint256;
    using SharesToTokens for Shares;

    // TODO: reorder arguments for clarity/consistency
    function getTransferShares(
        Tokens amount,
        BasisPoints taxRate,
        Tokens totalSupply,
        Shares totalShares,
        Shares fromShares,
        Shares toShares
    ) internal view returns (Shares newFromShares, Shares newToShares, Shares newTotalShares) {
        Shares uninvolvedShares = totalShares - fromShares - toShares;
        TokensXShares t1 = alloc().omul(fromShares, totalSupply);
        TokensXShares t2 = alloc().omul(amount, totalShares);
        TokensXShares t3 = alloc().osub(t1, t2);
        TokensXBasisPointsXShares2 n1 = alloc4().omul(t3, scale(uninvolvedShares, BASIS));
        TokensXBasisPointsXShares t4 = alloc3().omul(totalSupply, scale(uninvolvedShares, BASIS));
        TokensXBasisPointsXShares t5 = alloc3().omul(amount, scale(totalShares, taxRate));
        TokensXBasisPointsXShares d = alloc3().oadd(t4, t5);
        TokensXBasisPointsXShares t6 = alloc3().omul(amount, scale(totalShares, BASIS - taxRate));
        TokensXBasisPointsXShares t7 = alloc3().omul(scale(toShares, BASIS), totalSupply);
        TokensXBasisPointsXShares t8 = alloc3().oadd(t6, t7);
        TokensXBasisPointsXShares2 n2 = alloc4().omul(t8, uninvolvedShares);

        newFromShares = n1.div(d);
        newToShares = n2.div(d);
        // TODO: implement divMulti for TokensXBasisPointsXShares2 / TokensXBasisPointsXShares
        /*
        {
            (uint256 x, uint256 y) = cast(n1).divMulti(cast(n2), cast(d));
            (newFromShares, newToShares) = (Shares.wrap(x), Shares.wrap(y));
        }
        */
        newTotalShares = totalShares + (newToShares - toShares) - (fromShares - newFromShares);

        // TODO use divMulti to compute beforeToBalance and beforeFromBalance (can't use it for after because newTotalShares might change)
        Tokens beforeToBalance = toShares.toTokens(totalSupply, totalShares);
        Tokens afterToBalance = newToShares.toTokens(totalSupply, newTotalShares);
        Tokens expectedAfterToBalanceLo = beforeToBalance + amount - castUp(scale(amount, taxRate));
        //Tokens expectedAfterToBalanceHi = beforeToBalance + castUp(scale(amount, BASIS - taxRate));

        if (afterToBalance < expectedAfterToBalanceLo) {
            //console.log("branch 0");
            {
                //console.log("to round up");
                Shares incr = Shares.wrap(Shares.unwrap(newTotalShares).unsafeDiv(Tokens.unwrap(totalSupply)));
                newToShares = newToShares + incr;
                newTotalShares = newTotalShares + incr;
                //console.log("incr", Shares.unwrap(incr));
            }
            Tokens beforeFromBalance = fromShares.toTokens(totalSupply, totalShares);
            Tokens afterFromBalance = newFromShares.toTokens(totalSupply, newTotalShares);
            Tokens expectedAfterFromBalance = beforeFromBalance - amount;
            if (afterFromBalance < expectedAfterFromBalance) {
                //console.log("from round up");
                Shares incr = Shares.wrap(Shares.unwrap(newTotalShares).unsafeDiv(Tokens.unwrap(totalSupply)));
                newFromShares = newFromShares + incr;
                newTotalShares = newTotalShares + incr;
                //console.log("incr", Shares.unwrap(incr));
            }
        }
        // TODO: previously the block below was an `else` block. This is more accurate, but it is *MUCH* less gas efficient
        {
            //console.log("branch 1");
            Tokens beforeFromBalance = fromShares.toTokens(totalSupply, totalShares);
            Tokens afterFromBalance = newFromShares.toTokens(totalSupply, newTotalShares);
            Tokens expectedAfterFromBalance = beforeFromBalance - amount;
            {
                bool condition = afterFromBalance > expectedAfterFromBalance;
                if (condition) {
                    //console.log("from round down");
                }
                newFromShares = newFromShares.dec(condition);
                newTotalShares = newTotalShares.dec(condition);
            }
            {
                bool condition = afterFromBalance < expectedAfterFromBalance;
                if (condition) {
                    //console.log("from round up");
                }
                newFromShares = newFromShares.inc(condition);
                newTotalShares = newTotalShares.inc(condition);
            }

            afterToBalance = newToShares.toTokens(totalSupply, newTotalShares);
            {
                bool condition = afterToBalance > expectedAfterToBalanceLo;
                if (condition) {
                    //console.log("to round down");
                }
                newToShares = newToShares.dec(condition);
                newTotalShares = newTotalShares.dec(condition);
            }
            {
                bool condition = afterToBalance < expectedAfterToBalanceLo;
                if (condition) {
                    //console.log("to round up");
                }
                newToShares = newToShares.inc(condition);
                newTotalShares = newTotalShares.inc(condition);
            }

            afterFromBalance = newFromShares.toTokens(totalSupply, newTotalShares);
            {
                bool condition = afterFromBalance > expectedAfterFromBalance;
                if (condition) {
                    //console.log("from round down");
                }
                newFromShares = newFromShares.dec(condition);
                newTotalShares = newTotalShares.dec(condition);
            }
            {
                bool condition = afterFromBalance < expectedAfterFromBalance;
                if (condition) {
                    //console.log("from round up");
                }
                newFromShares = newFromShares.inc(condition);
                newTotalShares = newTotalShares.inc(condition);
            }

            /*
            afterToBalance = newToShares.toTokens(totalSupply, newTotalShares);
            {
                bool condition = afterToBalance > expectedAfterToBalanceLo;
                if (condition) {
                    //console.log("to round down");
                }
                newToShares = newToShares.dec(condition);
                newTotalShares = newTotalShares.dec(condition);
            }
            {
                bool condition = afterToBalance < expectedAfterToBalanceLo;
                if (condition) {
                    //console.log("to round up");
                }
                newToShares = newToShares.inc(condition);
                newTotalShares = newTotalShares.inc(condition);
            }
            */
        }

        if (newTotalShares > totalShares) {
            // TODO: check to see if this branch is still necessary
            //console.log("clamp");
            Shares decrTotal = newTotalShares - totalShares;
            Shares decrFrom;
            Shares decrTo;
            if (newFromShares > newToShares) {
                //console.log("clamp from");
                decrFrom = Shares.wrap(
                    Shares.unwrap(decrTotal) * Shares.unwrap(newFromShares)
                        / Shares.unwrap(newFromShares + newToShares)
                );
                decrTo = decrTotal - decrFrom;
            } else {
                //console.log("clamp to");
                decrTo = Shares.wrap(
                    Shares.unwrap(decrTotal) * Shares.unwrap(newToShares)
                        / Shares.unwrap(newFromShares + newToShares)
                );
                decrFrom = decrTotal - decrTo;
            }
            newTotalShares = totalShares;
            newFromShares = newFromShares - decrFrom;
            newToShares = newToShares - decrTo;
        }

        //console.log("===");
        //console.log("           taxRate", BasisPoints.unwrap(taxRate));
        //console.log("       totalSupply", Tokens.unwrap(totalSupply));
        //console.log("       totalShares", Shares.unwrap(totalShares));
        //console.log("    newTotalShares", Shares.unwrap(newTotalShares));
        //console.log("        fromShares", Shares.unwrap(fromShares));
        //console.log("     newFromShares", Shares.unwrap(newFromShares));
        //console.log("          toShares", Shares.unwrap(toShares));
        //console.log("       newToShares", Shares.unwrap(newToShares));
        //console.log("===");
    }

    function getTransferShares(
        BasisPoints taxRate,
        Tokens totalSupply,
        Shares totalShares,
        Shares fromShares,
        Shares toShares
    ) internal pure returns (Shares newToShares, Shares newTotalShares) {
        // Called when `from` is sending their entire balance
        Shares uninvolvedShares = totalShares - fromShares - toShares;
        Shares2XBasisPoints n = alloc5().omul(scale(uninvolvedShares, BASIS), totalShares);
        SharesXBasisPoints d = scale(uninvolvedShares, BASIS) + scale(fromShares, taxRate);

        /*
        Shares2XBasisPoints n =
            alloc5().omul(scale(fromShares, (BASIS - taxRate)) + scale(toShares, BASIS), uninvolvedShares);
        SharesXBasisPoints d = scale(uninvolvedShares, BASIS) + scale(fromShares, taxRate);
        newToShares = n.div(d);
        newTotalShares = totalShares + (newToShares - toShares) - fromShares;
        */
        newTotalShares = n.div(d);
        newToShares = toShares + fromShares - (totalShares - newTotalShares);

        //console.log("           taxRate", BasisPoints.unwrap(taxRate));
        //console.log("       totalSupply", Tokens.unwrap(totalSupply));
        //console.log("       totalShares", Shares.unwrap(totalShares));
        //console.log("        fromShares", Shares.unwrap(fromShares));
        //console.log("          toShares", Shares.unwrap(toShares));
        //console.log("       newToShares", Shares.unwrap(newToShares));
        //console.log("===");

        // Fixup rounding error
        // TODO: use divMulti
        Tokens beforeFromBalance = fromShares.toTokens(totalSupply, totalShares);
        Tokens beforeToBalance = toShares.toTokens(totalSupply, totalShares);
        Tokens afterToBalance = newToShares.toTokens(totalSupply, newTotalShares);
        Tokens expectedAfterToBalance = beforeToBalance + beforeFromBalance - castUp(scale(beforeFromBalance, taxRate));
        //Tokens expectedAfterToBalance = beforeToBalance + cast(scale(beforeFromBalance, BASIS - taxRate));

        //console.log("before fromBalance", Tokens.unwrap(beforeFromBalance));
        //console.log("  before toBalance", Tokens.unwrap(beforeToBalance));
        //console.log("         toBalance", Tokens.unwrap(afterToBalance));
        //console.log("expected toBalance", Tokens.unwrap(expectedAfterToBalance));

        /*
        {
            bool condition = afterToBalance > expectedAfterToBalance;
            newToShares = newToShares.dec(condition);
            newTotalShares = newTotalShares.dec(condition);
        }
        {
            bool condition = afterToBalance < expectedAfterToBalance;
            newToShares = newToShares.inc(condition);
            newTotalShares = newTotalShares.inc(condition);
        }
        */
        for (uint256 i; afterToBalance > expectedAfterToBalance && i < 3; i++) {
            //console.log("round down");
            // TODO: should this use `unsafeDiv` instead of `unsafeDivUp`? That might give lower rounding error (and consequently fewer iterations of this loop)
            Shares decr = Shares.wrap(
                (Tokens.unwrap(afterToBalance - expectedAfterToBalance) * Shares.unwrap(newTotalShares)).unsafeDivUp(
                    Tokens.unwrap(totalSupply)
                )
            );
            //console.log("decr", Shares.unwrap(decr));
            newToShares = newToShares - decr;
            newTotalShares = newTotalShares - decr;
            if (newToShares <= toShares) {
                //console.log("clamp");
                newTotalShares = newTotalShares + (toShares - newToShares);
                newToShares = toShares;
                afterToBalance = newToShares.toTokens(totalSupply, newTotalShares);
                //console.log("updated toBalance", Tokens.unwrap(afterToBalance));
                break;
            }
            afterToBalance = newToShares.toTokens(totalSupply, newTotalShares);
            //console.log("updated toBalance", Tokens.unwrap(afterToBalance));
        }
        {
            bool condition = afterToBalance < expectedAfterToBalance;
            if (condition) {
                //console.log("round up");
            }
            newToShares = newToShares.inc(condition);
            newTotalShares = newTotalShares.inc(condition);
        }

        //console.log("    new toBalance", Tokens.unwrap(newToShares.toTokens(totalSupply, newTotalShares)));
        //console.log("===");
    }

    function getTransferShares(
        Tokens amount,
        BasisPoints taxRate,
        Tokens totalSupply,
        Shares totalShares,
        Shares fromShares
    )
        internal
        view
        returns (Shares newFromShares, Shares counterfactualToShares, Shares newToShares, Shares newTotalShares)
    {
        // Called when `to`'s final shares will be the whale limit
        revert("unimplemented");
    }

    function getTransferShares(BasisPoints taxRate, Shares totalShares, Shares fromShares)
        internal
        pure
        returns (Shares counterfactualToShares, Shares newToShares, Shares newTotalShares)
    {
        // Called when `to`'s final shares will be the whale limit and `from` is sending their entire balance
        revert("unimplemented");
    }

    function getDeliverShares(Tokens amount, Tokens totalSupply, Shares totalShares, Shares fromShares)
        internal
        view
        returns (Shares newFromShares, Shares newTotalShares)
    {
        TokensXShares t1 = alloc().omul(fromShares, totalSupply);
        TokensXShares t2 = alloc().omul(amount, totalShares);
        TokensXShares t3 = alloc().osub(t1, t2);
        TokensXShares2 n = alloc2().omul(t3, totalShares - fromShares);
        TokensXShares t4 = alloc().omul(totalSupply, totalShares - fromShares);
        TokensXShares d = alloc().oadd(t4, t2);

        newFromShares = n.div(d);
        newTotalShares = totalShares - (fromShares - newFromShares);

        // Fixup rounding error
        Tokens beforeFromBalance = tmp().omul(fromShares, totalSupply).div(totalShares);
        Tokens afterFromBalance = tmp().omul(newFromShares, totalSupply).div(newTotalShares);
        Tokens expectedAfterFromBalance = beforeFromBalance - amount;
        bool condition = afterFromBalance < expectedAfterFromBalance;
        newFromShares = newFromShares.inc(condition);
        newTotalShares = newTotalShares.inc(condition);
    }

    // getDeliverShares(Tokens,Shares,Shares) is not provided because it's extremely straightforward

    function getDeliverSharesPairWhale(Tokens amount, Tokens totalSupply, Shares totalShares, Shares fromShares)
        internal
        view
        returns (Shares newFromShares, Shares newTotalShares)
    {
        revert("unimplemented");
    }

    function getBurnShares(Tokens amount, Tokens totalSupply, Shares totalShares, Shares fromShares)
        internal
        view
        returns (Shares)
    {
        TokensXShares t1 = alloc().omul(fromShares, totalSupply);
        TokensXShares t2 = alloc().omul(totalShares, amount);
        TokensXShares n = alloc().osub(t1, t2);
        return n.div(totalSupply);
    }

    // getBurnShares(Tokens,Shares,Shares) is not provided because it's extremely straightforward

    function getBurnSharesPairWhale(Tokens amount, Tokens totalSupply, Shares totalShares, Shares fromShares)
        internal
        view
        returns (Shares newFromShares, Shares newTotalShares)
    {
        revert("unimplemented");
    }
}
