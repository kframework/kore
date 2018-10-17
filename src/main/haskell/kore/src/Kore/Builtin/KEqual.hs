{- |
Module      : Kore.Builtin.KEqual
Description : Built-in KEQUAL operations
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
Maintainer  : traian.serbanuta@runtimeverification.com
Stability   : experimental
Portability : portable

This module is intended to be imported qualified, to avoid collision with other
builtin modules.

@
    import qualified Kore.Builtin.KEqual as KEqual
@
 -}
module Kore.Builtin.KEqual
    ( symbolVerifiers
    , builtinFunctions
    ) where

import qualified Data.HashMap.Strict as HashMap
import           Data.Map
                 ( Map )
import qualified Data.Map as Map
import           Data.Text
                 ( Text )

import           Kore.AST.Common
                 ( Application (..), PureMLPattern, SortedVariable )
import           Kore.AST.MetaOrObject
import qualified Kore.Builtin.Bool as Bool
import qualified Kore.Builtin.Builtin as Builtin
import qualified Kore.IndexedModule.MetadataTools as MetadataTools
import qualified Kore.Step.ExpandedPattern as ExpandedPattern
import           Kore.Step.Function.Data
                 ( ApplicationFunctionEvaluator (..), AttemptedFunction (..),
                 notApplicableFunctionEvaluator, purePatternFunctionEvaluator )
import qualified Kore.Step.OrOfExpandedPattern as OrOfExpandedPattern
import           Kore.Step.Simplification.Data
                 ( PredicateSubstitutionSimplifier, PureMLPatternSimplifier,
                 SimplificationProof (..), Simplifier )
import           Kore.Step.Simplification.Equals
                 ( makeEvaluate )
import           Kore.Step.StepperAttributes
                 ( StepperAttributes )
import           Kore.Substitution.Class
                 ( Hashable )
import           Kore.Variables.Fresh
                 ( FreshVariable )

{- | Verify that hooked symbol declarations are well-formed.

  See also: 'Builtin.verifySymbol'

 -}
symbolVerifiers :: Builtin.SymbolVerifiers
symbolVerifiers =
    HashMap.fromList
    [ ( "KEQUAL.eq"
      , Builtin.verifySymbol Bool.assertSort [trivialVerifier, trivialVerifier])
    , ("KEQUAL.neq"
      , Builtin.verifySymbol Bool.assertSort [trivialVerifier, trivialVerifier])
    ]
  where
    trivialVerifier :: Builtin.SortVerifier
    trivialVerifier = const $ const $ Right ()

{- | @builtinFunctions@ defines the hooks for @KEQUAL.eq@ and @KEQUAL.neq@
which can take arbitrary terms (of the same sort) and check whether they are
equal or not, producing a builtin boolean value.
 -}
builtinFunctions :: Map Text Builtin.Function
builtinFunctions =
    Map.fromList
    [ ("KEQUAL.eq", ApplicationFunctionEvaluator (evalKEq True False))
    , ("KEQUAL.neq", ApplicationFunctionEvaluator (evalKEq False True))
    ]

evalKEq
    ::  ( FreshVariable variable
        , Hashable variable
        , OrdMetaOrObject variable
        , SortedVariable variable
        , ShowMetaOrObject variable
        )
    => Bool
    -> Bool
    -> MetadataTools.MetadataTools Object StepperAttributes
    -> PredicateSubstitutionSimplifier level
    -> PureMLPatternSimplifier Object variable
    -> Application Object (PureMLPattern Object variable)
    -> Simplifier
        ( AttemptedFunction Object variable
        , SimplificationProof Object
        )
evalKEq true false tools _ _ pat =
    case pat of
        Application
            { applicationSymbolOrAlias =
                (MetadataTools.getResultSort tools -> resultSort)
            , applicationChildren = [t1, t2]
            } -> evalEq resultSort t1 t2
        _ -> notApplicableFunctionEvaluator
  where
    evalEq resultSort t1 t2 = do
        (result, _proof) <- makeEvaluate tools ep1 ep2
        if OrOfExpandedPattern.isTrue result
            then purePatternFunctionEvaluator (Bool.asPattern resultSort true)
        else if OrOfExpandedPattern.isFalse result
            then purePatternFunctionEvaluator (Bool.asPattern resultSort false)
        else notApplicableFunctionEvaluator
      where
        ep1 = ExpandedPattern.fromPurePattern t1
        ep2 = ExpandedPattern.fromPurePattern t2
