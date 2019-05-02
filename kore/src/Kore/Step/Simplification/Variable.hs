{-|
Module      : Kore.Step.Simplification.Variable
Description : Tools for Variable pattern simplification.
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
Maintainer  : virgil.serbanuta@runtimeverification.com
Stability   : experimental
Portability : portable
-}
module Kore.Step.Simplification.Variable
    ( simplify
    ) where

import           Kore.Internal.OrPattern
                 ( OrPattern )
import qualified Kore.Internal.OrPattern as OrPattern
import           Kore.Internal.TermLike

{-| 'simplify' simplifies a 'Variable' pattern, which means returning
an or containing a term made of that variable.
-}
simplify
    :: (Ord variable, SortedVariable variable)
    => variable
    -> OrPattern variable
simplify var = OrPattern.fromTermLike $ mkVar var
