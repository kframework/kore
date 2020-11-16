module Test.Kore.Step.Rule.Simplify
    ( test_simplifyRule_RewriteRule
    , test_simplifyRule_OnePathClaim
    , test_simplifyClaimRule
    ) where

import Prelude.Kore

import Test.Tasty

import Control.Applicative
    ( ZipList (..)
    )
import qualified Control.Lens as Lens
import Control.Monad.Morph
    ( MFunctor (..)
    )
import Control.Monad.Reader
    ( MonadReader
    , ReaderT
    , runReaderT
    )
import qualified Control.Monad.Reader as Reader
import qualified Data.Bifunctor as Bifunctor
import Data.Generics.Product
    ( field
    )

import Kore.Internal.Condition
    ( Condition
    , Conditional (..)
    )
import qualified Kore.Internal.Condition as Condition
import qualified Kore.Internal.MultiAnd as MultiAnd
import qualified Kore.Internal.MultiOr as MultiOr
import qualified Kore.Internal.OrPattern as OrPattern
import qualified Kore.Internal.Pattern as Pattern
import Kore.Internal.Predicate
    ( Predicate
    , makeAndPredicate
    , makeCeilPredicate
    , makeEqualsPredicate
    , makeNotPredicate
    , makeTruePredicate
    )
import qualified Kore.Internal.Predicate as Predicate
import qualified Kore.Internal.SideCondition as SideCondition
import qualified Kore.Internal.Substitution as Substitution
import Kore.Internal.TermLike
    ( AdjSomeVariableName
    , InternalVariable
    , TermLike
    , mkAnd
    , mkElemVar
    , mkEquals
    , mkOr
    , termLikeSort
    )
import qualified Kore.Internal.TermLike as TermLike
import Kore.Reachability
    ( OnePathClaim (..)
    , simplify
    )
import Kore.Rewriting.RewritingVariable
    ( RewritingVariableName
    , getRewritingVariable
    )
import Kore.Sort
    ( predicateSort
    )
import Kore.Step.ClaimPattern
    ( ClaimPattern (..)
    , mkClaimPattern
    )
import Kore.Step.Rule.Simplify
import Kore.Step.RulePattern
    ( RewriteRule
    )
import Kore.Step.Simplification.Data
    ( Env (..)
    )
import Kore.Step.Simplification.Simplify
    ( MonadSMT
    , MonadSimplify (..)
    , emptyConditionSimplifier
    )
import Kore.Step.Transition
    ( runTransitionT
    )
import Kore.Syntax.Variable
    ( VariableName
    , fromVariableName
    )
import Log

import qualified Test.Kore.Step.MockSymbols as Mock
import Test.Kore.Step.Rule.Common
    ( Pair (..)
    , RuleBase
    )
import qualified Test.Kore.Step.Rule.Common as Common
import Test.Kore.Step.Simplification
    ( runSimplifier
    , runSimplifierSMT
    )
import Test.Tasty.HUnit.Ext

test_simplifyRule_RewriteRule :: [TestTree]
test_simplifyRule_RewriteRule =
    [ testCase "No simplification needed" $ do
        let rule = Mock.a `rewritesToWithSortRewriteRule` Mock.cf
            expected = [rule]

        actual <- runSimplifyRule rule

        assertEqual "" expected actual

    , testCase "Simplify lhs term" $ do
        let expected = [Mock.a `rewritesToWithSortRewriteRule` Mock.cf]

        actual <- runSimplifyRule
            (   mkAnd Mock.a (mkEquals Mock.testSort Mock.a Mock.a)
                `rewritesToWithSortRewriteRule`
                Mock.cf
            )

        assertEqual "" expected actual

    , testCase "Does not simplify rhs term" $ do
        let rule =
                Mock.a
                `rewritesToWithSortRewriteRule`
                mkAnd Mock.cf (mkEquals Mock.testSort Mock.a Mock.a)
            expected = [rule]

        actual <- runSimplifyRule rule

        assertEqual "" expected actual

    , testCase "Substitution in lhs term" $ do
        let expected = [Mock.a `rewritesToWithSortRewriteRule` Mock.f Mock.b]

        actual <- runSimplifyRule
            (   mkAnd Mock.a (mkEquals Mock.testSort Mock.b x)
                `rewritesToWithSortRewriteRule` Mock.f x
            )

        assertEqual "" expected actual

    , testCase "Does not simplify ensures predicate" $ do
        let rule =
                Pair (Mock.a,  makeTruePredicate Mock.testSort)
                `rewritesToWithSortRewriteRule`
                Pair (Mock.cf, makeEqualsPredicate Mock.testSort Mock.b Mock.b)
            expected = [rule]

        actual <- runSimplifyRule rule

        assertEqual "" expected actual

    , testCase "Splits rule" $ do
        let expected =
                [ Mock.a `rewritesToWithSortRewriteRule` Mock.cf
                , Mock.b `rewritesToWithSortRewriteRule` Mock.cf
                ]

        actual <- runSimplifyRule
            (   mkOr Mock.a Mock.b
                `rewritesToWithSortRewriteRule`
                Mock.cf
            )

        assertEqual "" expected actual
    , testCase "f(x) is always defined" $ do
        let expected =
                [ Mock.functional10 x `rewritesToWithSortRewriteRule` Mock.a
                ]

        actual <- runSimplifyRule
            (   Pair (Mock.functional10 x, makeTruePredicate Mock.testSort)
                `rewritesToWithSortRewriteRule`
                Pair (Mock.a, makeTruePredicate Mock.testSort)
            )

        assertEqual "" expected actual
    ]
  where
    rewritesToWithSortRewriteRule
        :: RuleBase base (RewriteRule VariableName)
        => base VariableName
        -> base VariableName
        -> RewriteRule VariableName
    rewritesToWithSortRewriteRule = Common.rewritesToWithSort

    x = mkElemVar Mock.x

test_simplifyRule_OnePathClaim :: [TestTree]
test_simplifyRule_OnePathClaim =
    [ testCase "No simplification needed" $ do
        let rule = Mock.a `rewritesToWithSort` Mock.cf
            expected = [rule]

        actual <- runSimplifyRule rule

        assertEqual "" expected actual

    , testCase "Simplify lhs term" $ do
        let expected = [Mock.a `rewritesToWithSort` Mock.cf]

        actual <- runSimplifyRule
            (   mkAnd Mock.a (mkEquals Mock.testSort Mock.a Mock.a)
                `rewritesToWithSort`
                Mock.cf
            )

        assertEqual "" expected actual

    , testCase "Does not simplify rhs term" $ do
        let rule =
                Mock.a
                `rewritesToWithSort`
                mkAnd Mock.cf (mkEquals Mock.testSort Mock.a Mock.a)
            expected = [rule]

        actual <- runSimplifyRule rule

        assertEqual "" expected actual

    , testCase "Substitution in lhs term" $ do
        let expected = [Mock.a `rewritesToWithSort` Mock.f Mock.b]

        actual <- runSimplifyRule
            (   mkAnd Mock.a (mkEquals Mock.testSort Mock.b x)
                `rewritesToWithSort` Mock.f x
            )

        assertEqual "" expected actual

    , testCase "Simplifies requires predicate" $ do
        let expected = [Mock.a `rewritesToWithSort` Mock.cf]

        actual <- runSimplifyRule
            (   Pair (Mock.a,  makeEqualsPredicate Mock.testSort Mock.b Mock.b)
                `rewritesToWithSort`
                Pair (Mock.cf, makeTruePredicate Mock.testSort)
            )

        assertEqual "" expected actual

    , testCase "Does not simplify ensures predicate" $ do
        let rule =
                Pair (Mock.a,  makeTruePredicate Mock.testSort)
                `rewritesToWithSort`
                Pair (Mock.cf, makeEqualsPredicate Mock.testSort Mock.b Mock.b)
            expected = [rule]

        actual <- runSimplifyRule rule

        assertEqual "" expected actual

    , testCase "Substitution in requires predicate" $ do
        let expected = [Mock.a `rewritesToWithSort` Mock.f Mock.b]

        actual <- runSimplifyRuleSMT
            (   Pair (Mock.a,  makeEqualsPredicate Mock.testSort Mock.b x)
                `rewritesToWithSort`
                Pair (Mock.f x, makeTruePredicate Mock.testSort)
            )

        assertEqual "" expected actual

    , testCase "Splits rule" $ do
        let expected =
                [ Mock.a `rewritesToWithSort` Mock.cf
                , Mock.b `rewritesToWithSort` Mock.cf
                ]

        actual <- runSimplifyRule
            (   mkOr Mock.a Mock.b
                `rewritesToWithSort`
                Mock.cf
            )

        assertEqual "" expected actual
    , testCase "Case where f(x) is defined;\
               \ Case where it is not is simplified" $ do
        let expected =
                [   Pair (Mock.f x, makeCeilPredicate Mock.testSort (Mock.f x))
                    `rewritesToWithSort`
                    Pair (Mock.a, makeTruePredicate Mock.testSort)
                ]

        actual <- runSimplifyRuleSMT
            (   Pair (Mock.f x, makeTruePredicate Mock.testSort)
                `rewritesToWithSort`
                Pair (Mock.a, makeTruePredicate Mock.testSort)
            )

        assertEqual "" expected actual
    , testCase "lhs: f(x) is always defined" $ do
        let expected =
                [ Mock.functional10 x `rewritesToWithSort` Mock.a
                ]

        actual <- runSimplifyRule
            (   Pair (Mock.functional10 x, makeTruePredicate Mock.testSort)
                `rewritesToWithSort`
                Pair (Mock.a, makeTruePredicate Mock.testSort)
            )

        assertEqual "" expected actual
    , testCase "Predicate simplification removes trivial claim" $ do
        let expected = []
        actual <- runSimplifyRule
            ( Pair
                ( Mock.b
                , makeAndPredicate
                    (makeNotPredicate
                        (makeEqualsPredicate Mock.testSort x Mock.b)
                    )
                    (makeNotPredicate
                        (makeNotPredicate
                            (makeEqualsPredicate Mock.testSort x Mock.b)
                        )
                    )
                )
              `rewritesToWithSort`
              Pair (Mock.a, makeTruePredicate Mock.testSort)
            )
        assertEqual "" expected actual

    , testCase "rhs: f(x) is always defined" $ do
        let expected =
                [ Mock.a `rewritesToWithSort` Mock.functional10 x
                ]

        actual <- runSimplSMT
            (   Pair (Mock.a, makeTruePredicate Mock.testSort)
                `rewritesToWithSort`
                Pair (Mock.functional10 x, makeTruePredicate Mock.testSort)
            )

        assertEqual "" expected actual

    , testCase "infer rhs is defined" $ do
        let expected =
                [   Pair (Mock.a, makeTruePredicate Mock.testSort)
                    `rewritesToWithSort`
                    Pair (Mock.f x, makeCeilPredicate Mock.testSort (Mock.f x))
                ]

        actual <- runSimplSMT
            (   Pair (Mock.a, makeTruePredicate Mock.testSort)
                `rewritesToWithSort`
                Pair (Mock.f x, makeTruePredicate Mock.testSort)
            )

        assertEqual "" expected actual
    ]
  where
    simplClaim
        :: forall simplifier
        .  MonadSimplify simplifier
        => OnePathClaim
        -> simplifier [OnePathClaim]
    simplClaim claim =
        runTransitionT (simplify claim)
        & (fmap . fmap) fst

    runSimplSMT :: OnePathClaim -> IO [OnePathClaim]
    runSimplSMT claim =
        runSimplifierSMT Mock.env (simplClaim claim)

    rewritesToWithSort
        :: RuleBase base OnePathClaim
        => base VariableName
        -> base VariableName
        -> OnePathClaim
    rewritesToWithSort = Common.rewritesToWithSort

    x = mkElemVar Mock.x

runSimplifyRule
    :: SimplifyRuleLHS rule
    => rule
    -> IO [rule]
runSimplifyRule rule =
    fmap toList
    $ runSimplifier Mock.env
    $ simplifyRuleLhs rule

runSimplifyRuleSMT
    :: SimplifyRuleLHS rule
    => rule
    -> IO [rule]
runSimplifyRuleSMT rule =
    fmap toList
    $ runSimplifierSMT Mock.env
    $ simplifyRuleLhs rule

test_simplifyClaimRule :: [TestTree]
test_simplifyClaimRule =
    [ test "infers definedness" []
        rule1
        [rule1']
    , test "includes side condition" [(Mock.g Mock.a, Mock.f Mock.a)]
        rule2
        [rule2']
    ]
  where
    rule1, rule2, rule2' :: ClaimPattern
    rule1 =
        mkClaimPattern
            (Pattern.fromTermLike (Mock.f Mock.a))
            (OrPattern.fromPatterns [Pattern.fromTermLike Mock.b])
            []
    rule1' = rule1 & requireDefined
    rule2 =
        mkClaimPattern
            (Pattern.fromTermLike (Mock.g Mock.a))
            (OrPattern.fromPatterns [Pattern.fromTermLike Mock.b])
            []
        & require aEqualsb
    rule2' =
        rule2
        & requireDefined
        & Lens.over
            (field @"left")
            ( Pattern.andCondition
                (Mock.f Mock.a & Pattern.fromTermLike)
            . Pattern.withoutTerm
            )

    require condition =
        Lens.over
            (field @"left")
            (flip Pattern.andCondition condition)

    aEqualsb =
        makeEqualsPredicate Mock.testSort Mock.a Mock.b
        & Condition.fromPredicate

    requireDefined =
        Lens.over
            (field @"left")
            (\left' ->
                let leftTerm = Pattern.term left'
                    leftSort = TermLike.termLikeSort leftTerm
                 in Pattern.andCondition
                        left'
                        ( makeCeilPredicate leftSort leftTerm
                        & Condition.fromPredicate
                        )
            )

    test
        :: HasCallStack
        => TestName
        -> [(TermLike RewritingVariableName, TermLike RewritingVariableName)]
        -- ^ replacements
        -> ClaimPattern
        -> [ClaimPattern]
        -> TestTree
    test name replacements (OnePathClaim -> input) (map OnePathClaim -> expect) =
        -- Test simplifyClaimRule through the OnePathClaim instance.
        testCase name $ do
            actual <- run (simplifyRuleLhs input) & fmap toList
            -- Equivalent under associativity of \\and
            let checkEquivalence
                    (fmap getOnePathClaim -> claims1)
                    (fmap getOnePathClaim -> claims2)
                  =
                    and (areEquivalent <$> ZipList claims1 <*> ZipList claims2)
            assertEqual "" True (checkEquivalence expect actual)
      where
        run =
            runSimplifierSMT env
            . flip runReaderT TestEnv
                { replacements, input, requires = aEqualsb }
            . runTestSimplifierT
        env =
            Mock.env
                { simplifierCondition = emptyConditionSimplifier
                , simplifierAxioms = mempty
                }

data TestEnv =
    TestEnv
    { replacements
        :: ![(TermLike RewritingVariableName, TermLike RewritingVariableName)]
    , input :: !OnePathClaim
    , requires :: !(Condition RewritingVariableName)
    }

newtype TestSimplifierT m a =
    TestSimplifierT { runTestSimplifierT :: ReaderT TestEnv m a }
    deriving newtype (Functor, Applicative, Monad)
    deriving newtype (MonadReader TestEnv)
    deriving newtype (MonadLog, MonadSMT)

instance MonadTrans TestSimplifierT where
    lift = TestSimplifierT . lift

instance MFunctor TestSimplifierT where
    hoist f = TestSimplifierT . hoist f . runTestSimplifierT

instance MonadSimplify m => MonadSimplify (TestSimplifierT m) where
    simplifyTermLike sideCondition termLike = do
        TestEnv { replacements, input, requires } <- Reader.ask
        let rule = getOnePathClaim input
            leftTerm =
                Lens.view (field @"left") rule
                & Pattern.term
            sort = termLikeSort leftTerm
            expectSideCondition =
                makeAndPredicate
                    (Condition.toPredicate requires)
                    (makeCeilPredicate sort leftTerm)
                & liftPredicate
                & Predicate.coerceSort predicateSort
                & Condition.fromPredicate
                & SideCondition.fromCondition
            -- Equivalent under associativity of \\and
            checkEquivalence cond1 cond2 =
                (==)
                    (cond1 & SideCondition.toPredicate & MultiAnd.fromPredicate)
                    (cond2 & SideCondition.toPredicate & MultiAnd.fromPredicate)
            satisfied = checkEquivalence sideCondition expectSideCondition
        return
            . OrPattern.fromTermLike
            . (if satisfied then applyReplacements replacements else id)
            $ termLike
      where
        applyReplacements
            :: InternalVariable variable
            => [(TermLike RewritingVariableName, TermLike RewritingVariableName)]
            -> TermLike variable
            -> TermLike variable
        applyReplacements replacements zero =
            foldl' applyReplacement zero
            $ fmap liftReplacement replacements

        applyReplacement orig (ini, fin)
          | orig == ini = fin
          | otherwise   = orig

        liftPredicate
            :: InternalVariable variable
            => Predicate RewritingVariableName
            -> Predicate variable
        liftPredicate =
            Predicate.mapVariables liftRewritingVariable

        liftTermLike
            :: InternalVariable variable
            => TermLike RewritingVariableName
            -> TermLike variable
        liftTermLike =
            TermLike.mapVariables liftRewritingVariable

        liftReplacement
            :: InternalVariable variable
            => (TermLike RewritingVariableName, TermLike RewritingVariableName)
            -> (TermLike variable, TermLike variable)
        liftReplacement = Bifunctor.bimap liftTermLike liftTermLike

        liftRewritingVariable
            :: InternalVariable variable
            => AdjSomeVariableName (RewritingVariableName -> variable)
        liftRewritingVariable =
            pure (.) <*> pure fromVariableName <*> getRewritingVariable

-- | The terms of the implication are equivalent in respect to
-- the associativity, commutativity, and idempotence of \\and.
--
-- Warning: this should only be used when the distinction between the
-- predicate and substitution of a pattern is not of importance.
areEquivalent
    :: ClaimPattern
    -> ClaimPattern
    -> Bool
areEquivalent
    ClaimPattern
        { left = left1
        , right = right1
        , existentials = existentials1
        , attributes = attributes1
        }
    ClaimPattern
        { left = left2
        , right = right2
        , existentials = existentials2
        , attributes = attributes2
        }
  =
    let leftsAreEquivalent =
            toConjunctionOfTerms left1
            == toConjunctionOfTerms left2
        rightsAreEquivalent =
            MultiOr.map toConjunctionOfTerms right1
            == MultiOr.map toConjunctionOfTerms right2
     in leftsAreEquivalent
        && rightsAreEquivalent
        && existentials1 == existentials2
        && attributes1 == attributes2
  where
    toConjunctionOfTerms Conditional { term, predicate, substitution } =
        MultiAnd.fromTermLike term
        <> MultiAnd.fromTermLike (Predicate.unwrapPredicate predicate)
        <> MultiAnd.fromTermLike
            ( Predicate.unwrapPredicate
            . Substitution.toPredicate
            $ substitution
            )
