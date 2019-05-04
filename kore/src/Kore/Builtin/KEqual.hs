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
      -- * keys
    , eqKey
    , neqKey
    , iteKey
    ) where

import qualified Data.Functor.Foldable as Recursive
import qualified Data.HashMap.Strict as HashMap
import           Data.Map
                 ( Map )
import qualified Data.Map as Map
import           Data.String
                 ( IsString )
import           Data.Text
                 ( Text )

import           Kore.AST.Pure
import           Kore.AST.Valid
import           Kore.Attribute.Symbol
                 ( StepperAttributes )
import qualified Kore.Builtin.Bool as Bool
import           Kore.Builtin.Builtin
                 ( acceptAnySort )
import qualified Kore.Builtin.Builtin as Builtin
import qualified Kore.Error
import qualified Kore.IndexedModule.MetadataTools as MetadataTools
import qualified Kore.Predicate.Predicate as Predicate
import           Kore.Step.Axiom.Data
                 ( AttemptedAxiom (..), AttemptedAxiomResults (..),
                 BuiltinAndAxiomSimplifierMap, applicationAxiomSimplifier,
                 notApplicableAxiomEvaluator, purePatternAxiomEvaluator )
import qualified Kore.Step.OrPattern as OrPattern
import           Kore.Step.Pattern
                 ( Conditional (..) )
import           Kore.Step.Simplification.Data
                 ( PredicateSimplifier, Simplifier, TermLikeSimplifier )
import qualified Kore.Step.Simplification.Or as Or
import           Kore.Step.TermLike
import           Kore.Syntax.Definition
                 ( SentenceSymbol (..) )
import           Kore.Unparser
import           Kore.Variables.Fresh
                 ( FreshVariable )

{- | Verify that hooked symbol declarations are well-formed.

  See also: 'Builtin.verifySymbol'

 -}
symbolVerifiers :: Builtin.SymbolVerifiers
symbolVerifiers =
    HashMap.fromList
    [ ( eqKey
      , Builtin.verifySymbol Bool.assertSort [acceptAnySort, acceptAnySort])
    , (neqKey
      , Builtin.verifySymbol Bool.assertSort [acceptAnySort, acceptAnySort])
    , (iteKey, iteVerifier)
    ]
  where
    iteVerifier :: Builtin.SymbolVerifier
    iteVerifier
        findSort
        SentenceSymbol
            { sentenceSymbolSorts = sorts
            , sentenceSymbolResultSort = result
            }
      =
        Kore.Error.withContext "In argument sorts" $
            case sorts of
                [firstSort, secondSort, thirdSort] -> do
                    Bool.assertSort findSort firstSort
                    Kore.Error.koreFailWhen
                        (secondSort /= thirdSort)
                        "Expected continuations to match"
                    Kore.Error.koreFailWhen
                        (secondSort /= result)
                        "Expected continuations to match"
                    return ()
                _ ->
                    Kore.Error.koreFail
                        ( "Wrong arity, expected 3 but got "
                        ++ show arity ++ " in KEQUAL.ite"
                        )
      where
        arity = length sorts

{- | @builtinFunctions@ defines the hooks for @KEQUAL.eq@, @KEQUAL.neq@, and
@KEQUAL.ite@.

@KEQUAL.eq@ and @KEQUAL.neq@ can take arbitrary terms (of the same sort) and
check whether they are equal or not, producing a builtin boolean value.

@KEQUAL.ite@ can take a boolean expression and two arbitrary terms (of the same
sort) and return the first term if the expression is true, and the second
otherwise.
 -}
builtinFunctions :: Map Text Builtin.Function
builtinFunctions =
    Map.fromList
    [ (eqKey, applicationAxiomSimplifier (evalKEq True))
    , (neqKey, applicationAxiomSimplifier (evalKEq False))
    , (iteKey, applicationAxiomSimplifier evalKIte)
    ]

evalKEq
    ::  ( FreshVariable variable
        , SortedVariable variable
        , Unparse variable
        , Show variable
        )
    => Bool
    -> MetadataTools.SmtMetadataTools StepperAttributes
    -> PredicateSimplifier
    -> TermLikeSimplifier
    -- ^ Evaluates functions.
    -> BuiltinAndAxiomSimplifierMap
    -- ^ Map from symbol IDs to defined functions
    -> CofreeF
        (Application SymbolOrAlias)
        (Valid variable)
        (TermLike variable)
    -> Simplifier (AttemptedAxiom variable)
evalKEq true _ _ _ _ (valid :< app) =
    case applicationChildren of
        [t1, t2] -> evalEq t1 t2
        _ -> Builtin.wrongArity (if true then eqKey else neqKey)
  where
    false = not true
    Valid { patternSort } = valid
    Application { applicationChildren } = app
    evalEq t1 t2 = do
        let expr = Or.simplifyEvaluated
                (OrPattern.fromPattern
                    (Conditional
                        (Bool.asInternal patternSort true)
                        (Predicate.makeEqualsPredicate t1 t2)
                        mempty
                    )
                )
                (OrPattern.fromPattern
                    (Conditional
                        (Bool.asInternal patternSort false)
                        ( Predicate.makeNotPredicate $
                            Predicate.makeEqualsPredicate t1 t2
                        )
                        mempty
                    )
                )
        pure $ Applied AttemptedAxiomResults
            { results = expr
            , remainders = OrPattern.bottom
            }

evalKIte
    ::  forall variable
    .   ( FreshVariable variable
        , SortedVariable variable
        )
    => MetadataTools.SmtMetadataTools StepperAttributes
    -> PredicateSimplifier
    -> TermLikeSimplifier
    -> BuiltinAndAxiomSimplifierMap
    -- ^ Map from symbol IDs to defined functions
    -> CofreeF
        (Application SymbolOrAlias)
        (Valid variable)
        (TermLike variable)
    -> Simplifier (AttemptedAxiom variable)
evalKIte _ _ _ _ (_ :< app) =
    case app of
        Application { applicationChildren = [expr, t1, t2] } ->
            evalIte expr t1 t2
        _ -> Builtin.wrongArity iteKey
  where
    evaluate
        :: TermLike variable
        -> Maybe Bool
    evaluate (Recursive.project -> _ :< pat) =
        case pat of
            DomainValuePattern dv ->
                Just (Bool.extractBoolDomainValue iteKey dv)
            _ -> Nothing

    evalIte expr t1 t2 =
        case evaluate expr of
            Just result
                | result    -> purePatternAxiomEvaluator t1
                | otherwise -> purePatternAxiomEvaluator t2
            Nothing    -> notApplicableAxiomEvaluator

eqKey :: IsString s => s
eqKey = "KEQUAL.eq"

neqKey :: IsString s => s
neqKey = "KEQUAL.neq"

iteKey :: IsString s => s
iteKey = "KEQUAL.ite"
