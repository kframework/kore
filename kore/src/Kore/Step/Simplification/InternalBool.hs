{-# LANGUAGE Strict #-}

{- |
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
-}
module Kore.Step.Simplification.InternalBool (
    simplify,
) where

import Prelude.Kore

import Kore.Internal.InternalBool
import Kore.Internal.OrPattern (
    OrPattern,
 )
import qualified Kore.Internal.OrPattern as OrPattern
import Kore.Internal.TermLike
import Kore.Rewriting.RewritingVariable (
    RewritingVariableName,
 )

simplify ::
    InternalBool ->
    OrPattern RewritingVariableName
simplify = OrPattern.fromPattern . pure . mkInternalBool
