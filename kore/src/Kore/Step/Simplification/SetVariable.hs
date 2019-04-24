{-|
Module      : Kore.Step.Simplification.SetVariable
Description : Tools for SetVariable pattern simplification.
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
Maintainer  : virgil.serbanuta@runtimeverification.com
Stability   : experimental
Portability : portable
-}
module Kore.Step.Simplification.SetVariable
    ( simplify
    ) where

import           Kore.AST.Pure
import           Kore.AST.Valid
import           Kore.Predicate.Predicate
                 ( makeTruePredicate )
import           Kore.Step.Representation.ExpandedPattern
                 ( Predicated (..) )
import qualified Kore.Step.Representation.MultiOr as MultiOr
                 ( make )
import           Kore.Step.Representation.OrOfExpandedPattern
                 ( OrOfExpandedPattern )
import           Kore.Step.Simplification.Data
                 ( SimplificationProof (..) )

{-| 'simplify' simplifies a 'Variable' pattern, which means returning
an or containing a term made of that variable.
-}
simplify
    :: (MetaOrObject level, Ord (variable level), SortedVariable variable)
    => SetVariable variable level
    -> ( OrOfExpandedPattern level variable
       , SimplificationProof level
       )
simplify (SetVariable var) =
    ( MultiOr.make
        [Predicated
            { term = mkSetVar var
            , predicate = makeTruePredicate
            , substitution = mempty
            }
        ]
    , SimplificationProof
    )
