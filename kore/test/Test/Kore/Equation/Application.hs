module Test.Kore.Equation.Application
    ( test_attemptEquation
    , test_attemptEquationUnification
    , concrete
    , symbolic
    , axiom
    , axiom_
    , functionAxiomUnification
    , functionAxiomUnification_
    ) where

import Prelude.Kore

import Test.Tasty

import qualified Control.Lens as Lens
import Control.Monad
    ( (>=>)
    )
import Data.Generics.Product
    ( field
    )
import Data.Text
    ( Text
    )
import GHC.Natural
    ( intToNatural
    )

import Data.Sup
    ( Sup (..)
    )
import Kore.Attribute.Axiom.Concrete
    ( Concrete (..)
    )
import Kore.Attribute.Axiom.Symbolic
    ( Symbolic (..)
    )
import Kore.Equation.Application hiding
    ( attemptEquation
    )
import qualified Kore.Equation.Application as Equation
import Kore.Equation.Equation
import qualified Kore.Internal.Condition as Condition
import Kore.Internal.Pattern as Pattern
import Kore.Internal.TermLike
import qualified Kore.Internal.TermLike as TermLike
import qualified Kore.Variables.Target as Target
import qualified Pretty

import Test.Expect
import Test.Kore
    ( testId
    )
import Test.Kore.Internal.Pattern as Pattern
import Test.Kore.Internal.Predicate as Predicate
import Test.Kore.Internal.SideCondition as SideCondition
import qualified Test.Kore.Step.MockSymbols as Mock
import Test.Kore.Step.Simplification
import Test.Tasty.HUnit.Ext

type Equation' = Equation VariableName
type AttemptEquationError' = AttemptEquationError VariableName
type AttemptEquationResult' = AttemptEquationResult VariableName

attemptEquation
    :: TestSideCondition
    -> TestTerm
    -> Equation'
    -> IO AttemptEquationResult'
attemptEquation sideCondition termLike equation =
    Equation.attemptEquation sideCondition termLike' equation
    & runSimplifier Mock.env
  where
    termLike' = TermLike.mapVariables Target.mkUnifiedNonTarget termLike

assertNotMatched :: AttemptEquationError' -> Assertion
assertNotMatched (WhileMatch _) = return ()
assertNotMatched result =
    (assertFailure . show . Pretty.vsep)
        [ "Expected (WhileMatch _), but found:"
        , Pretty.indent 4 (debug result)
        ]

assertApplyMatchResultErrors :: AttemptEquationError' -> Assertion
assertApplyMatchResultErrors (WhileApplyMatchResult _) = return ()
assertApplyMatchResultErrors result =
    (assertFailure . show . Pretty.vsep)
        [ "Expected (WhileApplyMatch _), but found:"
        , Pretty.indent 4 (debug result)
        ]

assertRequiresNotMet :: AttemptEquationError' -> Assertion
assertRequiresNotMet (WhileCheckRequires _) = return ()
assertRequiresNotMet result =
    (assertFailure . show . Pretty.vsep)
        [ "Expected (RequiresNotMet _ _), but found:"
        , Pretty.indent 4 (debug result)
        ]

test_attemptEquation :: [TestTree]
test_attemptEquation =
    [ applies "applies identity axiom"
        (axiom_ x x)
        SideCondition.top
        x
        (Pattern.fromTermLike x)

    , applies "applies identity without renaming"
        (axiom_ x x)
        SideCondition.top
        y
        (Pattern.fromTermLike y)

    , applies "Σ(X, X) => X applies to Σ(f(X), f(X))"
        (axiom_ (sigma x x) x)
        SideCondition.top
        (sigma (f x) (f x))
        (Pattern.fromTermLike $ f x)

    , notMatched "merge configuration patterns"
        (axiom_ (sigma x x) x)
        SideCondition.top
        (sigma x (f x))

    , notMatched "substitution with symbol matching"
        (axiom_ (sigma x x) x)
        SideCondition.top
        (sigma (f y) (f z))

    , notMatched "merge multiple variables"
        (axiom_ (sigma (sigma x x) (sigma y y)) (sigma x y))
        SideCondition.top
        (sigma (sigma x y) (sigma y x))

    , notMatched "symbol clash"
        (axiom_ (sigma x x) x)
        SideCondition.top
        (sigma (f x) (g x))

    , notMatched "impossible substitution"
        (axiom_ (sigma (sigma x x) (sigma y y)) (sigma x y))
        SideCondition.top
        (sigma (sigma x (f y)) (sigma x y))

    , notMatched "circular dependency error"
        (axiom_ (sigma x x) x)
        SideCondition.top
        (sigma x (f x))

    , notMatched "non-function substitution error"
        (axiom_ (sigma x x) x)
        SideCondition.top
        (sigma x (f y))

    , notMatched "unify all children"
        (axiom_ (sigma x x) x)
        SideCondition.top
        (sigma (sigma x x) (sigma (sigma y z) (sigma y y)))

    , notMatched "normalize substitution"
        (axiom_ (sigma (sigma x x) y) (sigma x y))
        SideCondition.top
        (sigma (sigma x (f b)) x)

    , notMatched "merge substitution with initial"
        (axiom_ (sigma (sigma x x) y) (sigma x y))
        SideCondition.top
        (sigma (sigma (f z) (f y)) (f z))

    , notMatched "unmatched strings"
        (axiom_ (string "Good-bye, world!") xString)
        SideCondition.top
        (string "Hello, world!")

    , testCase "conjoin rule ensures" $ do
        let
            ensures =
                makeEqualsPredicate_
                    (Mock.functional11 (mkElemVar Mock.x))
                    (Mock.functional10 (mkElemVar Mock.x))
            expect =
                Pattern.withCondition initial
                $ Condition.fromPredicate
                $ makeEqualsPredicate Mock.testSort
                    (Mock.functional11 (mkElemVar Mock.y))
                    (Mock.functional10 (mkElemVar Mock.y))
            initial = mkElemVar Mock.y
            equation = equationId { ensures }
        attemptEquation SideCondition.top initial equation
            >>= expectRight >>= assertEqual "" expect

    , testCase "equation requirement" $ do
        let
            requires =
                makeEqualsPredicate sortR
                    (Mock.functional11 (mkElemVar Mock.x))
                    (Mock.functional10 (mkElemVar Mock.x))
            equation = equationId { requires }
            initial = Mock.a
        let requires1 =
                makeEqualsPredicate sortR
                    (Mock.functional11 Mock.a)
                    (Mock.functional10 Mock.a)
            expect1 =
                WhileCheckRequires CheckRequiresError
                { matchPredicate = makeTruePredicate_
                , equationRequires = requires1
                , sideCondition = SideCondition.top
                }
        attemptEquation SideCondition.top initial equation
            >>= expectLeft >>= assertEqual "" expect1
        let requires2 =
                makeEqualsPredicate sortR
                    (Mock.functional11 Mock.a)
                    (Mock.functional10 Mock.a)
            sideCondition2 =
                SideCondition.fromCondition . Condition.fromPredicate
                $ requires2
            expect2 = Pattern.fromTermLike initial
        attemptEquation sideCondition2 initial equation
            >>= expectRight >>= assertEqual "" expect2

    , testCase "rule a => \\bottom" $ do
        let expect =
                Pattern.withCondition (mkBottom Mock.testSort)
                $ Condition.topOf Mock.testSort
            initial = Mock.a
        attemptEquation SideCondition.top initial equationBottom
            >>= expectRight >>= assertEqual "" expect

    , testCase "rule a => b ensures \\bottom" $ do
        let expect =
                Pattern.withCondition Mock.b
                $ Condition.bottomOf Mock.testSort
            initial = Mock.a
        attemptEquation SideCondition.top initial equationEnsuresBottom
            >>= expectRight >>= assertEqual "" expect

    , testCase "rule a => b requires \\bottom" $ do
        let expect =
                WhileCheckRequires CheckRequiresError
                    { matchPredicate = makeTruePredicate_
                    , equationRequires = makeFalsePredicate sortR
                    , sideCondition = SideCondition.top
                    }
            initial = Mock.a
        attemptEquation SideCondition.top initial equationRequiresBottom
            >>= expectLeft >>= assertEqual "" expect

    , testCase "rule a => \\bottom does not apply to c" $ do
        let initial = Mock.c
        attemptEquation SideCondition.top initial equationRequiresBottom
            >>= expectLeft >>= assertNotMatched
    , applies "F(x) => G(x) applies to F(x)"
        (axiom_ (f x) (g x))
        SideCondition.top
        (f x)
        (Pattern.fromTermLike $ g x)
    , applies "F(x) => G(x) [symbolic(x)] applies to F(x)"
        (axiom_ (f x) (g x) & symbolic [x])
        SideCondition.top
        (f x)
        (Pattern.fromTermLike $ g x)
    , notInstantiated "F(x) => G(x) [concrete(x)] doesn't apply to F(x)"
        (axiom_ (f x) (g x) & concrete [x])
        SideCondition.top
        (f x)
    , notInstantiated "F(x) => G(x) [concrete] doesn't apply to f(cf)"
        (axiom_ (f x) (g x) & concrete [x])
        SideCondition.top
        (f cf)
    , notMatched "F(x) => G(x) doesn't apply to F(top)"
        (axiom_ (f x) (g x))
        SideCondition.top
        (f mkTop_)
    , applies "F(x) => G(x) [concrete] applies to F(a)"
        (axiom_ (f x) (g x) & concrete [x])
        SideCondition.top
        (f a)
        (Pattern.fromTermLike $ g a)
    , applies
        "Σ(X, Y) => A [symbolic(x), concrete(Y)]"
        (axiom_ (sigma x y) a & symbolic [x] & concrete [y])
        SideCondition.top
        (sigma x a)
        (Pattern.fromTermLike a)
    , notInstantiated
        "Σ(X, Y) => A [symbolic(x), concrete(Y)]"
        (axiom_ (sigma x y) a & symbolic [x] & concrete [y])
        SideCondition.top
        (sigma a a)
    , notInstantiated
        "Σ(X, Y) => A [symbolic(x), concrete(Y)]"
        (axiom_ (sigma x y) a & symbolic [x] & concrete [y])
        SideCondition.top
        (sigma x x)
    , requiresNotMet "F(x) => G(x) requires \\bottom doesn't apply to F(x)"
        (axiom (f x) (g x) (makeFalsePredicate sortR))
        SideCondition.top
        (f x)
    , notMatched "Σ(X, X) => G(X) doesn't apply to Σ(Y, Z) -- no narrowing"
        (axiom_ (sigma x x) (g x))
        SideCondition.top
        (sigma y z)
    , requiresNotMet
        -- using SMT
        "Σ(X, Y) => A requires (X > 0 and not Y > 0) doesn't apply to Σ(Z, Z)"
        (axiom (sigma x y) a (positive x `andNot` positive y))
        SideCondition.top
        (sigma z z)
    , applies
        -- using SMT
        "Σ(X, Y) => A requires (X > 0 or not Y > 0) applies to Σ(Z, Z)"
        (axiom (sigma x y) a (positive x `orNot` positive y))
        (SideCondition.fromPredicate $ positive a)
        (sigma a a)
        -- SMT not used to simplify trivial constraints
        (Pattern.fromTermLike a)
    , requiresNotMet
        -- using SMT
        "f(X) => A requires (X > 0) doesn't apply to f(Z) and (not (Z > 0))"
        (axiom (f x) a (positive x))
        (SideCondition.fromPredicate $ makeNotPredicate (positive z))
        (f z)
    , applies
        -- using SMT
        "f(X) => A requires (X > 0) applies to f(Z) and (Z > 0)"
        (axiom (f x) a (positive x))
        (SideCondition.fromPredicate $ positive z)
        (f z)
        (Pattern.fromTermLike a)
    , testCase "X => X does not apply to X / X" $ do
        let initial = tdivInt xInt xInt
        attemptEquation SideCondition.top initial equationId
            >>= expectLeft >>= assertRequiresNotMet
    , testCase "X => X does apply to X / X if \\ceil(X / X)" $ do
        let initial = tdivInt xInt xInt
            sideCondition =
                makeCeilPredicate_ initial
                & SideCondition.fromPredicate
            expect = Pattern.fromTermLike initial
        attemptEquation sideCondition initial equationId
            >>= expectRight >>= assertEqual "" expect
    , notInstantiated "does not introduce variables"
        (axiom_ (f a) (g x))
        SideCondition.top
        (f a)
    ]

test_attemptEquationUnification :: [TestTree]
test_attemptEquationUnification =
    [ applies "Σ(X, X) => X applies to Σ(f(X), f(X))"
        (functionAxiomUnification_ sigmaSymbol [x, x] x)
        SideCondition.top
        (sigma (f x) (f x))
        (Pattern.fromTermLike $ f x)

    , notMatched "merge configuration patterns"
        (functionAxiomUnification_ sigmaSymbol [x, x] x)
        SideCondition.top
        (sigma x (f x))

    , notInstantiated "substitution with symbol matching"
        (functionAxiomUnification_ sigmaSymbol [x, x] x)
        SideCondition.top
        (sigma (f y) (f z))

    , notInstantiated "merge multiple variables"
        (functionAxiomUnification_ sigmaSymbol [sigma x x, sigma y y] (sigma x y))
        SideCondition.top
        (sigma (sigma x y) (sigma y x))

    , notMatched "symbol clash"
        (functionAxiomUnification_ sigmaSymbol [x, x] x)
        SideCondition.top
        (sigma (f x) (g x))

    , notMatched "impossible substitution"
        (functionAxiomUnification_ sigmaSymbol [sigma x x, sigma y y] (sigma x y))
        SideCondition.top
        (sigma (sigma x (f y)) (sigma x y))

    , notMatched "circular dependency error"
        (functionAxiomUnification_ sigmaSymbol [x, x] x)
        SideCondition.top
        (sigma x (f x))

    , notInstantiated "non-function substitution error"
        (functionAxiomUnification_ sigmaSymbol [x, x] x)
        SideCondition.top
        (sigma x (f y))

    , notInstantiated "unify all children"
        (functionAxiomUnification_ sigmaSymbol [x, x] x)
        SideCondition.top
        (sigma (sigma x x) (sigma (sigma y z) (sigma y y)))

    , notInstantiated "normalize substitution"
        (functionAxiomUnification_ sigmaSymbol [sigma x x, y] (sigma x y))
        SideCondition.top
        (sigma (sigma x (f b)) x)

    , notInstantiated "merge substitution with initial"
        (functionAxiomUnification_ sigmaSymbol [sigma x x, y] (sigma x y))
        SideCondition.top
        (sigma (sigma (f z) (f y)) (f z))

    , testCase "rule a => \\bottom" $ do
        let expect =
                Pattern.withCondition (mkBottom Mock.testSort)
                $ Condition.topOf Mock.testSort
            initial = Mock.a
        attemptEquation SideCondition.top initial equationBottom
            >>= expectRight >>= assertEqual "" expect

    , applies "F(x) => G(x) applies to F(x)"
        (functionAxiomUnification_ fSymbol [x] (g x))
        SideCondition.top
        (f x)
        (Pattern.fromTermLike $ g x)
    , applies "F(x) => G(x) [symbolic(x)] applies to F(x)"
        (functionAxiomUnification_ fSymbol [x] (g x) & symbolic [x])
        SideCondition.top
        (f x)
        (Pattern.fromTermLike $ g x)
    , notInstantiated "F(x) => G(x) [concrete(x)] doesn't apply to F(x)"
        (functionAxiomUnification_ fSymbol [x] (g x) & concrete [x])
        SideCondition.top
        (f x)
    , notInstantiated "F(x) => G(x) [concrete] doesn't apply to f(cf)"
        (functionAxiomUnification_ fSymbol [x] (g x) & concrete [x])
        SideCondition.top
        (f cf)
    , notMatched "F(x) => G(x) doesn't apply to F(top)"
        (functionAxiomUnification_ fSymbol [x] (g x))
        SideCondition.top
        (f mkTop_)
    , applies "F(x) => G(x) [concrete] applies to F(a)"
        (functionAxiomUnification_ fSymbol [x] (g x) & concrete [x])
        SideCondition.top
        (f a)
        (Pattern.fromTermLike $ g a)
    , applies
        "Σ(X, Y) => A [symbolic(x), concrete(Y)]"
        (functionAxiomUnification_
            sigmaSymbol [x, y] a & symbolic [x] & concrete [y]
        )
        SideCondition.top
        (sigma x a)
        (Pattern.fromTermLike a)
    , notInstantiated
        "Σ(X, Y) => A [symbolic(x), concrete(Y)]"
        (functionAxiomUnification_
            sigmaSymbol [x, y] a & symbolic [x] & concrete [y]
        )
        SideCondition.top
        (sigma a a)
    , notInstantiated
        "Σ(X, Y) => A [symbolic(x), concrete(Y)]"
        (functionAxiomUnification_
            sigmaSymbol [x, y] a & symbolic [x] & concrete [y]
        )
        SideCondition.top
        (sigma x x)
    , requiresNotMet "F(x) => G(x) requires \\bottom doesn't apply to F(x)"
        (functionAxiomUnification fSymbol [x] (g x) (makeFalsePredicate sortR))
        SideCondition.top
        (f x)
    , notInstantiated "Σ(X, X) => G(X) doesn't apply to Σ(Y, Z) -- no narrowing"
        (functionAxiomUnification_ sigmaSymbol [x, x] (g x))
        SideCondition.top
        (sigma y z)
    , requiresNotMet
        -- using SMT
        "Σ(X, Y) => A requires (X > 0 and not Y > 0) doesn't apply to Σ(Z, Z)"
        (functionAxiomUnification
            sigmaSymbol [x, y] a (positive x `andNot` positive y)
        )
        SideCondition.top
        (sigma z z)
    , applies
        -- using SMT
        "Σ(X, Y) => A requires (X > 0 or not Y > 0) applies to Σ(Z, Z)"
        (functionAxiomUnification
            sigmaSymbol [x, y] a (positive x `orNot` positive y)
        )
        (SideCondition.fromPredicate $ positive a)
        (sigma a a)
        -- SMT not used to simplify trivial constraints
        (Pattern.fromTermLike a)
    , requiresNotMet
        -- using SMT
        "f(X) => A requires (X > 0) doesn't apply to f(Z) and (not (Z > 0))"
        (functionAxiomUnification fSymbol [x] a (positive x))
        (SideCondition.fromPredicate $ makeNotPredicate (positive z))
        (f z)
    , applies
        -- using SMT
        "f(X) => A requires (X > 0) applies to f(Z) and (Z > 0)"
        (functionAxiomUnification fSymbol [x] a (positive x))
        (SideCondition.fromPredicate $ positive z)
        (f z)
        (Pattern.fromTermLike a)
    , notInstantiated "does not introduce variables"
        (functionAxiomUnification_ fSymbol [a] (g x))
        SideCondition.top
        (f a)
    ]

-- * Test data

equationId :: Equation'
equationId = mkEquation sortR (mkElemVar Mock.x) (mkElemVar Mock.x)

equationRequiresBottom :: Equation'
equationRequiresBottom =
    (mkEquation sortR Mock.a Mock.b)
        { requires = makeFalsePredicate sortR }

equationEnsuresBottom :: Equation'
equationEnsuresBottom =
    (mkEquation sortR Mock.a Mock.b)
        { ensures = makeFalsePredicate sortR }

equationBottom :: Equation'
equationBottom =
    mkEquation sortR Mock.a (mkBottom Mock.testSort)

sortR :: Sort
sortR = mkSortVariable (testId "R")

f, g :: TestTerm -> TestTerm
f = Mock.functionalConstr10
g = Mock.functionalConstr11

fSymbol :: Symbol
fSymbol = Mock.functionalConstr10Symbol

cf :: TestTerm
cf = Mock.cf

sigma :: TestTerm -> TestTerm -> TestTerm
sigma = Mock.functionalConstr20

sigmaSymbol :: Symbol
sigmaSymbol = Mock.functionalConstr20Symbol

string :: Text -> TestTerm
string = Mock.builtinString

x, xString, xInt, y, z :: TestTerm
x = mkElemVar Mock.x
xInt = mkElemVar Mock.xInt
xString = mkElemVar Mock.xString
y = mkElemVar Mock.y
z = mkElemVar Mock.z

a, b :: TestTerm
a = Mock.a
b = Mock.b

tdivInt :: TestTerm -> TestTerm -> TestTerm
tdivInt = Mock.tdivInt

positive :: TestTerm -> TestPredicate
positive u' =
    makeEqualsPredicate Mock.testSort
        (Mock.lessInt
            (Mock.fTestInt u')  -- wrap the given term for sort agreement
            (Mock.builtinInt 0)
        )
        (Mock.builtinBool False)

andNot, orNot
    :: TestPredicate
    -> TestPredicate
    -> TestPredicate
andNot p1 p2 = makeAndPredicate p1 (makeNotPredicate p2)
orNot p1 p2 = makeOrPredicate p1 (makeNotPredicate p2)

-- * Helpers

axiom
    :: TestTerm
    -> TestTerm
    -> TestPredicate
    -> Equation'
axiom left right requires =
    (mkEquation sortR left right) { requires }

axiom_
    :: TestTerm
    -> TestTerm
    -> Equation'
axiom_ left right = axiom left right (makeTruePredicate sortR)

functionAxiomUnification
    :: Symbol
    -> [TestTerm]
    -> TestTerm
    -> TestPredicate
    -> Equation'
functionAxiomUnification symbol args right requires =
    case args of
        [] -> (mkEquation sortR (mkApplySymbol symbol []) right) { requires }
        _  -> (mkEquation sortR left right) { requires, argument }
  where
    left = mkApplySymbol symbol variables
    sorts = fmap termLikeSort args
    variables = generateVariables (intToNatural (length args)) sorts
    generateVariables n sorts' =
        fmap makeElementVariable (zip [0..n - 1] sorts')
    argument =
        Just
        $ foldr1 makeAndPredicate
        $ fmap (uncurry (makeInPredicate sortR))
        $ zip variables args
    makeElementVariable (num, sort) =
        mkElementVariable' (testId "funcVar") num sort
        & mkElemVar
    mkElementVariable' base counter variableSort =
        Variable
            { variableName =
                ElementVariableName
                    VariableName { base, counter = Just (Element counter) }
            , variableSort
            }

functionAxiomUnification_
    :: Symbol
    -> [TestTerm]
    -> TestTerm
    -> Equation'
functionAxiomUnification_ symbol args right =
    functionAxiomUnification symbol args right (makeTruePredicate sortR)

concrete :: [TestTerm] -> Equation' -> Equation'
concrete vars =
    Lens.set
        (field @"attributes" . field @"concrete")
        (Concrete $ foldMap freeVariables vars)

symbolic :: [TestTerm] -> Equation' -> Equation'
symbolic vars =
    Lens.set
        (field @"attributes" . field @"symbolic")
        (Symbolic $ foldMap freeVariables vars)

-- * Test cases

withAttemptEquationResult
    :: (AttemptEquationResult' -> Assertion)
    -> TestName
    -> Equation'
    -> TestSideCondition
    -> TestTerm
    -> TestTree
withAttemptEquationResult check testName equation sideCondition initial =
    testCase testName (attemptEquation sideCondition initial equation >>= check)

applies
    :: TestName
    -> Equation'
    -> TestSideCondition
    -> TestTerm
    -> TestPattern
    -> TestTree
applies testName equation sideCondition initial expect =
    withAttemptEquationResult
        (expectRight >=> assertEqual "" expect)
        testName
        equation
        sideCondition
        initial

notMatched
    :: TestName
    -> Equation'
    -> TestSideCondition
    -> TestTerm
    -> TestTree
notMatched = withAttemptEquationResult (expectLeft >=> assertNotMatched)

notInstantiated
    :: TestName
    -> Equation'
    -> TestSideCondition
    -> TestTerm
    -> TestTree
notInstantiated =
    withAttemptEquationResult (expectLeft >=> assertApplyMatchResultErrors)

requiresNotMet
    :: TestName
    -> Equation'
    -> TestSideCondition
    -> TestTerm
    -> TestTree
requiresNotMet =
    withAttemptEquationResult (expectLeft >=> assertRequiresNotMet)
