module Test.Kore.Reachability.SomeClaim
    ( test_extractClaim
    ) where

import Prelude.Kore

import Test.Tasty

import Data.Default
    ( def
    )

import qualified Kore.Internal.OrPattern as OrPattern
import qualified Kore.Internal.Pattern as Pattern
import Kore.Internal.Predicate
    ( makeEqualsPredicate_
    , makeNotPredicate
    , makeTruePredicate_
    , unwrapPredicate
    )
import Kore.Internal.TermLike
import Kore.Reachability.SomeClaim
import Kore.Rewriting.RewritingVariable
    ( mkRuleVariable
    )
import Kore.Step.ClaimPattern
    ( ClaimPattern (..)
    )
import Kore.Syntax.Sentence
    ( SentenceAxiom (..)
    , SentenceClaim (..)
    )

import Test.Expect
import qualified Test.Kore.Step.MockSymbols as Mock
import Test.Tasty.HUnit.Ext

test_extractClaim :: [TestTree]
test_extractClaim =
    [ test "without constraints"
        Mock.a
        makeTruePredicate_
        []
        [Mock.b]
        makeTruePredicate_
    , test "with constraints"
        Mock.a
        (makeEqualsPredicate_ (mkElemVar Mock.x) Mock.c)
        []
        [Mock.b]
        (makeNotPredicate (makeEqualsPredicate_ (mkElemVar Mock.x) Mock.a))
    , test "with existentials"
        Mock.a
        (makeEqualsPredicate_ (mkElemVar Mock.x) Mock.c)
        [Mock.z, Mock.y]
        [Mock.f (mkElemVar Mock.z)]
        (makeNotPredicate
            (makeEqualsPredicate_ (mkElemVar Mock.x) (mkElemVar Mock.z))
        )
    , test "with branching"
        Mock.a
        (makeEqualsPredicate_ (mkElemVar Mock.x) Mock.c)
        [Mock.z, Mock.y]
        [Mock.f (mkElemVar Mock.z), Mock.g (mkElemVar Mock.y)]
        (makeNotPredicate
            (makeEqualsPredicate_ (mkElemVar Mock.x) (mkElemVar Mock.z))
        )
    ]
  where
    mkPattern term predicate =
        Pattern.fromTermAndPredicate term predicate
        & Pattern.mapVariables (pure mkRuleVariable)
        & Pattern.syncSort
    test name leftTerm requires existentials rightTerms ensures =
        testCase name $ do
            let rightTerm = foldr1 mkOr rightTerms
                termLike =
                    mkImplies
                        (mkAnd (unwrapPredicate requires) leftTerm)
                        (applyModality WAF
                            (foldr
                                mkExists
                                (mkAnd (unwrapPredicate ensures) rightTerm)
                                existentials
                            )
                        )
                sentence =
                    SentenceClaim SentenceAxiom
                    { sentenceAxiomParameters = []
                    , sentenceAxiomPattern = termLike
                    , sentenceAxiomAttributes = mempty
                    }
                expect =
                    (AllPath . AllPathClaim)
                    ClaimPattern
                    { left = mkPattern leftTerm requires
                    , right =
                        OrPattern.fromPatterns
                        (map (\term -> mkPattern term ensures) rightTerms)
                    , existentials =
                        mapElementVariable (pure mkRuleVariable)
                        <$> existentials
                    , attributes = def
                    }
            actual <- expectJust $ extractClaim (def, sentence)
            assertEqual "" expect actual
