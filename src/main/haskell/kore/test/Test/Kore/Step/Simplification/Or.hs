module Test.Kore.Step.Simplification.Or where

import Test.Kore
       ( testId )
import Test.Tasty
import Test.Tasty.HUnit
import Test.Terse

import qualified Data.List as List
import           Data.Text
                 ( Text )

import           Kore.AST.Pure
import           Kore.AST.Valid
import qualified Kore.Domain.Builtin as Domain
import           Kore.Predicate.Predicate
                 ( CommonPredicate, makeEqualsPredicate, makeFalsePredicate,
                 makeOrPredicate, makeTruePredicate )
import           Kore.Step.ExpandedPattern
                 ( ExpandedPattern, Predicated (..), isBottom, isTop )
import           Kore.Step.OrOfExpandedPattern
                 ( MultiOr (..), OrOfExpandedPattern )
import           Kore.Step.Simplification.Or
                 ( simplify, simplifyEvaluated )
import           Kore.Unification.Substitution
                 ( Substitution )
import qualified Kore.Unification.Substitution as Substitution

import           Kore.Step.Simplification.Data
                 ( SimplificationProof (..) )
import           Test.Kore.Comparators ()
import qualified Test.Kore.Step.MockSymbols as Mock

          {- Part 1: `SimplifyEvaluated` is the core function. It converts two
             `OrOfExpandedPattern` values into a simplifier that is to
             produce a single `OrOfExpandedPattern`. We run the simplifier to
             check correctness.
          -}

-- Key for variable names:
-- 1. `OrOfExpandedPattern` values are represented by a tuple containing
--    the term, predicate, and substitution, in that order. They're
--    also tagged with `t`, `p`, and `s`.
-- 2. The second character has this meaning:
--    T : top
--    _ : bottom
--    m or M : a character neither top nor bottom. Two values
--             named `pm` and `pM` are expected to be unequal.

test_highestTop :: TestTree
test_highestTop =
  testGroup "Top dominates only when all its components are top"
  [ ((tT, pT, sT), (tm, pm, sm)) `simplifiesTo_` (tT, pT, sT)
  , ((tm, pm, sm), (tT, pT, sT)) `simplifiesTo_` (tT, pT, sT)
  , ((tT, pT, sT), (tT, pT, sT)) `simplifiesTo_` (tT, pT, sT)
  ]

test_mergePredicates :: TestTree
test_mergePredicates =
    testGroup "Merge predicates when first term is Top and substitutions are equal"
    [ ((tT, pM, sT), (tm, pm, sT)) `simplifiesTo_` (tT, makeOrPredicate pM pm, sT)
    -- This fails because the halfSimplifyEvaluated is not commutative:
    -- , ((tm, pm, sT), (tT, pM, sT)) `simplifiesTo_` (tT, makeOrPredicate pm pM, sT)
    , ((tT, pM, sm), (tm, pm, sm)) `simplifiesTo_` (tT, makeOrPredicate pM pm, sm)
    , testGroup "Inequal substitutions prevent merging"
        [ ((tT, pM, sT), (tm, pm, sm)) `becomes_` MultiOr [orChild (tT, pM, sT), orChild (tm, pm, sm)]
        , ((tm, pm, sm), (tT, pM, sT)) `becomes_` MultiOr [orChild (tT, pM, sT), orChild (tm, pm, sm)]
        ]
    ]

test_anyBottom :: TestTree
test_anyBottom =
  testGroup "Any bottom is removed from the result"
  [ ((tM, pM, sM), (t_, pm, sm)) `simplifiesTo_` (tM, pM, sM)
  , ((tM, pM, sM), (tm, p_, sm)) `simplifiesTo_` (tM, pM, sM)

  , ((t_, pm, sm), (tM, pM, sM)) `simplifiesTo_` (tM, pM, sM)
  , ((tm, p_, sm), (tM, pM, sM)) `simplifiesTo_` (tM, pM, sM)

  -- Both bottom turns into an empty multiOr
  , ((t_, pm, sm), (tm, p_, sm)) `becomes_` (MultiOr [])

  , testGroup "check this test's expectations"
    [ orChild (t_, pm, sm) `satisfies_` isBottom
    , orChild (tm, p_, sm) `satisfies_` isBottom
      -- Note that it's impossible for the substitution to be bottom.
    ]
  ]

test_distinctMiddle :: TestTree
test_distinctMiddle =
    testGroup "Distinct middle patterns are not simplified"
    [ ((tM, pm, sm), (tm, pm, sm)) `becomes_` MultiOr [orChild (tM, pm, sm), orChild (tm, pm, sm)]
    , ((tm, pM, sm), (tm, pm, sm)) `becomes_` MultiOr [orChild (tm, pM, sm), orChild (tm, pm, sm)]
    , ((tm, pm, sM), (tm, pm, sm)) `becomes_` MultiOr [orChild (tm, pm, sM), orChild (tm, pm, sm)]
    ]

test_deduplicateMiddle :: TestTree
test_deduplicateMiddle =
    testGroup "Middle patterns are deduplicated"
    [ ((tM, pM, sM), (tM, pM, sM)) `becomes_` MultiOr [orChild (tM, pM, sM)]
    , ((tm, pm, sm), (tm, pm, sm)) `becomes_` MultiOr [orChild (tm, pm, sm)]
    ]


        {- Part 2: `simplify` is just a trivial use of `simplifyEvaluated` -}

test_simplify :: TestTree
test_simplify =
  testGroup "`simplify` just calls `simplifyEvaluated`"
  [
    equals_
      (simplify $        binaryOr orPattern1 orPattern2 )
      (simplifyEvaluated          orPattern1 orPattern2 )
  ]
  where
    orPattern1 :: OrOfExpandedPattern Object Variable
    orPattern1 = wrapInOrPattern (tM, pM, sM)
    
    orPattern2 :: OrOfExpandedPattern Object Variable
    orPattern2 = wrapInOrPattern (tm, pm, sm)

    binaryOr
      :: OrOfExpandedPattern Object Variable
      -> OrOfExpandedPattern Object Variable
      -> Or Object (OrOfExpandedPattern Object Variable)
    binaryOr first second =
        Or { orFirst = first
           , orSecond = second
           , orSort = Mock.testSort
           }


        {- Part 3: The values and functions relevant to this test -}



type TestTerm =
  PurePattern Object Domain.Builtin Variable (Valid (Variable Object) Object)

tT :: TestTerm
tT = mkTop Mock.testSort

tm :: TestTerm
tm = mkVar Mock.x

tM :: TestTerm
tM = mkVar Mock.y

t_ :: TestTerm
t_ = mkBottom Mock.testSort

testVar :: Text -> Variable Object
testVar ident = Variable (testId ident) Mock.testSort

type TestPredicate = CommonPredicate Object

pT :: TestPredicate
pT = makeTruePredicate

pm :: TestPredicate
pm =
  makeEqualsPredicate
    (mkVar $ testVar "left")
    (mkVar $ testVar "right")

pM :: TestPredicate
pM =
  makeEqualsPredicate
    (mkVar $ testVar "LEFT")
    (mkVar $ testVar "RIGHT")

p_ :: TestPredicate
p_ = makeFalsePredicate


type TestSubstitution = Substitution Object Variable

sT :: TestSubstitution
sT = mempty

sm :: TestSubstitution
sm = Substitution.wrap [(Mock.x, Mock.a)] -- I'd rather these were meaningful

sM :: TestSubstitution
sM = Substitution.wrap [(Mock.y, Mock.b)] -- I'd rather these were meaningful


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


                        -- Functions

orChild
  :: (TestTerm, TestPredicate, TestSubstitution)
  -> ExpandedPattern Object Variable
orChild (term, predicate, substitution) =
  Predicated
  { term = term
  , predicate = predicate
  , substitution = substitution
  }


-- Note: we intentionally take care *not* to simplify out tops or bottoms
-- during conversion of a Predicated into an OrOfExpandedPattern
wrapInOrPattern
  :: (TestTerm, TestPredicate, TestSubstitution)
  -> OrOfExpandedPattern Object Variable
wrapInOrPattern tuple =
    MultiOr [orChild tuple]


simplifiesTo_
  :: HasCallStack
  => ( (TestTerm, TestPredicate, TestSubstitution)
     , (TestTerm, TestPredicate, TestSubstitution)
     )
  -> (TestTerm, TestPredicate, TestSubstitution)
  -> TestTree
simplifiesTo_ tuples rawExpected =
  becomes_ tuples $ wrapInOrPattern rawExpected

becomes_
  :: HasCallStack
  => ( (TestTerm, TestPredicate, TestSubstitution)
     , (TestTerm, TestPredicate, TestSubstitution)
     )
  -> OrOfExpandedPattern Object Variable
  -> TestTree
becomes_ (raw1, raw2) (MultiOr expected) =
  let
    or1 = wrapInOrPattern raw1
    or2 = wrapInOrPattern raw2
  in
    equals_
      (simplifyEvaluated or1 or2)
      (MultiOr $ List.sort expected, SimplificationProof)
