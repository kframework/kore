module Test.Kore.Step.Simplification.Or
    ( test_anyBottom
    , test_deduplicateMiddle
    , test_simplify
    , test_valueProperties
    ) where

import Prelude.Kore

import Test.Kore
    ( testId
    )
import Test.Tasty
import Test.Tasty.HUnit
import Test.Terse

import qualified Data.List as List
import Data.Text
    ( Text
    )
import qualified Data.Text.Prettyprint.Doc as Pretty

import Kore.Internal.OrPattern
    ( OrPattern
    )
import qualified Kore.Internal.OrPattern as OrPattern
import Kore.Internal.Pattern as Pattern
import Kore.Internal.Predicate
    ( Predicate
    , makeEqualsPredicate_
    , makeFalsePredicate_
    , makeTruePredicate_
    )
import Kore.Internal.Substitution
    ( Substitution
    )
import qualified Kore.Internal.Substitution as Substitution
import Kore.Internal.TermLike
import Kore.Step.Simplification.Or
    ( simplify
    , simplifyEvaluated
    )
import qualified Kore.Unparser as Unparser
import Kore.Variables.UnifiedVariable
    ( UnifiedVariable (..)
    )

import qualified Test.Kore.Step.MockSymbols as Mock

-- * Part 1: 'simplifyEvaluated'

{-

`SimplifyEvaluated` is the core function. It converts two `OrPattern`
values into a simplifier that is to produce a single `OrPattern`. We
run the simplifier to check correctness.

-}

test_anyBottom :: TestTree
test_anyBottom =
    testGroup "Any bottom is removed from the result"
        [ ((tM, pM, sM), (t_, pm, sm)) `simplifiesTo` (tM, pM, sM)
        , ((tM, pM, sM), (tm, p_, sm)) `simplifiesTo` (tM, pM, sM)

        , ((t_, pm, sm), (tM, pM, sM)) `simplifiesTo` (tM, pM, sM)
        , ((tm, p_, sm), (tM, pM, sM)) `simplifiesTo` (tM, pM, sM)

        -- Both bottom turns into an empty multiOr
        , ((t_, pm, sm), (tm, p_, sm)) `becomes` []

        , testGroup "check this test's expectations"
            [ orChild (t_, pm, sm) `satisfies_` isBottom
            , orChild (tm, p_, sm) `satisfies_` isBottom
            -- Note that it's impossible for the substitution to be bottom.
            ]
        ]

test_deduplicateMiddle :: TestTree
test_deduplicateMiddle =
    testGroup "Middle patterns are deduplicated"
        [ ((tM, pM, sM), (tM, pM, sM)) `simplifiesTo` (tM, pM, sM)
        , ((tm, pm, sm), (tm, pm, sm)) `simplifiesTo` (tm, pm, sm)
        ]


-- * Part 2: `simplify` is just a trivial use of `simplifyEvaluated`

test_simplify :: TestTree
test_simplify =
    testGroup "`simplify` just calls `simplifyEvaluated`"
        [ equals_
            (simplify $        binaryOr orPattern1 orPattern2 )
            (simplifyEvaluated          orPattern1 orPattern2 )
        ]
  where
    orPattern1 :: OrPattern Variable
    orPattern1 = wrapInOrPattern (tM, pM, sM)

    orPattern2 :: OrPattern Variable
    orPattern2 = wrapInOrPattern (tm, pm, sm)

    binaryOr
      :: OrPattern Variable
      -> OrPattern Variable
      -> Or Sort (OrPattern Variable)
    binaryOr orFirst orSecond =
        Or { orSort = Mock.testSort, orFirst, orSecond }


-- * Part 3: The values and functions relevant to this test

{-
Key for variable names:
1. `OrPattern` values are represented by a tuple containing
   the term, predicate, and substitution, in that order. They're
   also tagged with `t`, `p`, and `s`.
2. The second character has this meaning:
   T : top
   _ : bottom
   m or M : a character neither top nor bottom. Two values
            named `pm` and `pM` are expected to be unequal.
-}

{- | Short-hand for: @Pattern Variable@

See also: 'orChild'
 -}
type TestConfig = (TestTerm, TestPredicate, TestSubstitution)

type TestTerm = TermLike Variable

tT :: TestTerm
tT = mkTop Mock.testSort

tm :: TestTerm
tm = mkElemVar Mock.x

tM :: TestTerm
tM = mkElemVar Mock.y

t_ :: TestTerm
t_ = mkBottom Mock.testSort

testVar :: Text -> ElementVariable Variable
testVar ident = ElementVariable $ Variable (testId ident) mempty Mock.testSort

type TestPredicate = Predicate Variable

pT :: TestPredicate
pT = makeTruePredicate_

pm :: TestPredicate
pm =
    makeEqualsPredicate_
        (mkElemVar $ testVar "left")
        (mkElemVar $ testVar "right")

pM :: TestPredicate
pM =
    makeEqualsPredicate_
        (mkElemVar $ testVar "LEFT")
        (mkElemVar $ testVar "RIGHT")

p_ :: TestPredicate
p_ = makeFalsePredicate_

type TestSubstitution = Substitution Variable

sT :: TestSubstitution
sT = mempty

sm :: TestSubstitution
sm = Substitution.wrap [(ElemVar Mock.x, Mock.a)] -- I'd rather these were meaningful

sM :: TestSubstitution
sM = Substitution.wrap [(ElemVar Mock.y, Mock.b)] -- I'd rather these were meaningful

test_valueProperties :: TestTree
test_valueProperties =
    testGroup "The values have properties that fit their ids"
        [ tT `has_` [ (isTop, True),   (isBottom, False) ]
        , tm `has_` [ (isTop, False),  (isBottom, False) ]
        , tM `has_` [ (isTop, False),  (isBottom, False) ]
        , t_ `has_` [ (isTop, False),  (isBottom, True) ]
        , tm `unequals_` tM

        , pT `has_` [ (isTop, True),   (isBottom, False) ]
        , pm `has_` [ (isTop, False),  (isBottom, False) ]
        , pM `has_` [ (isTop, False),  (isBottom, False) ]
        , p_ `has_` [ (isTop, False),  (isBottom, True) ]
        , pm `unequals_` pM

        , sT `has_` [ (isTop, True),   (isBottom, False) ]
        , sm `has_` [ (isTop, False),  (isBottom, False) ]
        , sM `has_` [ (isTop, False),  (isBottom, False) ]
        , sm `unequals_` sM
        -- There is no bottom substitution
        ]


-- * Test functions

becomes
  :: HasCallStack
  => (TestConfig, TestConfig)
  -> [Pattern Variable]
  -> TestTree
becomes
    (orChild -> or1, orChild -> or2)
    (OrPattern.fromPatterns . List.sort -> expected)
  =
    actual_expected_name_intention
        (simplifyEvaluated
            (OrPattern.fromPattern or1)
            (OrPattern.fromPattern or2)
        )
        expected
        "or becomes"
        (stateIntention
            [ prettyOr or1 or2
            , "to become:"
            , Unparser.unparse $ OrPattern.toPattern expected
            ]
        )

simplifiesTo
    :: HasCallStack
    => (TestConfig, TestConfig)
    -> TestConfig
    -> TestTree
simplifiesTo (orChild -> or1, orChild -> or2) (orChild -> simplified) =
    actual_expected_name_intention
        (simplifyEvaluated
            (OrPattern.fromPattern or1)
            (OrPattern.fromPattern or2)
        )
        (OrPattern.fromPattern simplified)
        "or does simplify"
        (stateIntention
            [ prettyOr or1 or2
            , "to simplify to:"
            , Unparser.unparse simplified
            ]
        )

-- * Support Functions

prettyOr
    :: Pattern Variable
    -> Pattern Variable
    -> Pretty.Doc a
prettyOr orFirst orSecond =
    Unparser.unparse Or { orSort, orFirst, orSecond }
  where
    orSort = termLikeSort (Pattern.term orFirst)

stateIntention :: [Pretty.Doc ann] -> String
stateIntention actualAndSoOn =
    Unparser.renderDefault $ Pretty.vsep ("expected: " : actualAndSoOn)

orChild
    :: (TestTerm, TestPredicate, TestSubstitution)
    -> Pattern Variable
orChild (term, predicate, substitution) =
    Conditional { term, predicate, substitution }

-- Note: we intentionally take care *not* to simplify out tops or bottoms
-- during conversion of a Conditional into an OrPattern
wrapInOrPattern
    :: (TestTerm, TestPredicate, TestSubstitution)
    -> OrPattern Variable
wrapInOrPattern tuple = OrPattern.fromPatterns [orChild tuple]
