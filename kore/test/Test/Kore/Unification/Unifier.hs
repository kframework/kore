module Test.Kore.Unification.Unifier
    ( test_unification
    , test_unsupportedConstructs
    ) where

import Test.Tasty
       ( TestName, TestTree, testGroup )
import Test.Tasty.HUnit
import Test.Tasty.HUnit.Extensions

import           Control.Exception
                 ( ErrorCall (ErrorCall), catch, evaluate )
import qualified Data.Bifunctor as Bifunctor
import           Data.List.NonEmpty
                 ( NonEmpty ((:|)) )
import qualified Data.Map as Map
import qualified Data.Set as Set
import           Data.Text
                 ( Text )

import           Kore.Attribute.Constructor
import           Kore.Attribute.Function
import           Kore.Attribute.Functional
import           Kore.Attribute.Injective
import           Kore.Attribute.SortInjection
import           Kore.Attribute.Symbol
import           Kore.IndexedModule.MetadataTools
import qualified Kore.IndexedModule.MetadataTools as HeadType
                 ( HeadType (..) )
import qualified Kore.Internal.MultiOr as MultiOr
import           Kore.Internal.Pattern as Pattern
import           Kore.Internal.TermLike hiding
                 ( V )
import qualified Kore.Predicate.Predicate as Syntax.Predicate
import qualified Kore.Predicate.Predicate as Syntax
                 ( Predicate )
import           Kore.Step.Axiom.Data
                 ( BuiltinAndAxiomSimplifierMap )
import           Kore.Step.Simplification.Data
                 ( evalSimplifier )
import qualified Kore.Step.Simplification.Pattern as Pattern
import qualified Kore.Step.Simplification.Simplifier as Simplifier
import           Kore.Unification.Error
import           Kore.Unification.Procedure
import qualified Kore.Unification.Substitution as Substitution
import           Kore.Unification.UnifierImpl
import qualified Kore.Unification.Unify as Monad.Unify
import           SMT
                 ( SMT )
import qualified SMT

import           Test.Kore
import           Test.Kore.ASTVerifier.DefinitionVerifier
import           Test.Kore.Comparators ()
import qualified Test.Kore.Step.MockSimplifiers as Mock

applyInj
    :: Sort
    -> TermLike Variable
    -> TermLike Variable
applyInj sortTo pat =
    applySymbol symbolInj [sortFrom, sortTo] [pat]
  where
    sortFrom = termLikeSort pat

s1, s2, s3, s4 :: Sort
s1 = simpleSort (SortName "s1")
s2 = simpleSort (SortName "s2")
s3 = simpleSort (SortName "s3")
s4 = simpleSort (SortName "s4")

a1, a2, a3, a4, a5 :: SentenceSymbol (TermLike Variable)
a1 = mkSymbol_ (testId "a1") [] s1
a2 = mkSymbol_ (testId "a2") [] s1
a3 = mkSymbol_ (testId "a3") [] s1
a4 = mkSymbol_ (testId "a4") [] s1
a5 = mkSymbol_ (testId "a5") [] s1

a, b, f :: SentenceSymbol (TermLike Variable)
a = mkSymbol_ (testId "a") [] s1
b = mkSymbol_ (testId "b") [] s2
f = mkSymbol_ (testId "f") [s1] s2

ef, eg, eh :: SentenceSymbol (TermLike Variable)
ef = mkSymbol_ (testId "ef") [s1, s1, s1] s1
eg = mkSymbol_ (testId "eg") [s1] s1
eh = mkSymbol_ (testId "eh") [s1] s1

nonLinF, nonLinG, nonLinAS :: SentenceSymbol (TermLike Variable)
nonLinF  = mkSymbol_ (testId "nonLinF") [s1, s1] s1
nonLinG  = mkSymbol_ (testId "nonLinG") [s1] s1
nonLinAS = mkSymbol_ (testId "nonLinA") [] s1

nonLinA, nonLinX, nonLinY :: TermLike Variable
nonLinA = applySymbol_ nonLinAS []
nonLinX = mkVar Variable { variableName = testId "x", variableCounter = mempty, variableSort = s1 }
nonLinY = mkVar Variable { variableName = testId "y", variableCounter = mempty, variableSort = s1 }

expBin :: SentenceSymbol (TermLike Variable)
expBin = mkSymbol_ (testId "times") [s1, s1] s1

expA, expX, expY :: TermLike Variable
expA = mkVar Variable { variableName = testId "a", variableCounter = mempty, variableSort = s1 }
expX = mkVar Variable { variableName = testId "x", variableCounter = mempty, variableSort = s1 }
expY = mkVar Variable { variableName = testId "y", variableCounter = mempty, variableSort = s1 }

ex1, ex2, ex3, ex4 :: TermLike Variable
ex1 = mkVar Variable { variableName = testId "ex1", variableCounter = mempty, variableSort = s1 }
ex2 = mkVar Variable { variableName = testId "ex2", variableCounter = mempty, variableSort = s1 }
ex3 = mkVar Variable { variableName = testId "ex3", variableCounter = mempty, variableSort = s1 }
ex4 = mkVar Variable { variableName = testId "ex4", variableCounter = mempty, variableSort = s1 }


dv1, dv2 :: TermLike Variable
dv1 =
    mkDomainValue DomainValue
        { domainValueSort = s1
        , domainValueChild = mkStringLiteral "dv1"
        }
dv2 =
    mkDomainValue DomainValue
        { domainValueSort = s1
        , domainValueChild = mkStringLiteral "dv2"
        }

aA :: TermLike Variable
aA = applySymbol_ a []

a1A :: TermLike Variable
a1A = applySymbol_ a1 []

a2A :: TermLike Variable
a2A = applySymbol_ a2 []

a3A :: TermLike Variable
a3A = applySymbol_ a3 []

a4A :: TermLike Variable
a4A = applySymbol_ a4 []

a5A :: TermLike Variable
a5A = applySymbol_ a5 []

bA :: TermLike Variable
bA = applySymbol_ b []

x :: TermLike Variable
x = mkVar Variable { variableName = testId "x", variableCounter = mempty, variableSort = s1 }

xs2 :: TermLike Variable
xs2 = mkVar Variable { variableName = testId "xs2", variableCounter = mempty, variableSort = s2 }

sortParam :: Text -> SortVariable
sortParam name = SortVariable (testId name)

sortParamSort :: Text -> Sort
sortParamSort = SortVariableSort . sortParam

injName :: Text
injName = "inj"

symbolInj :: SentenceSymbol (TermLike Variable)
symbolInj =
    mkSymbol
        (testId injName)
        [sortParam "From", sortParam "To"]
        [sortParamSort "From"]
        (sortParamSort "To")

isInjHead :: SymbolOrAlias -> Bool
isInjHead pHead = getId (symbolOrAliasConstructor pHead) == injName

mockStepperAttributes :: SymbolOrAlias -> StepperAttributes
mockStepperAttributes patternHead =
    defaultSymbolAttributes
        { constructor = Constructor { isConstructor }
        , functional = Functional { isDeclaredFunctional }
        , function = Function { isDeclaredFunction }
        , injective = Injective { isDeclaredInjective }
        , sortInjection = SortInjection { isSortInjection }
        }
  where
    isConstructor =
            patternHead /= getSentenceSymbolOrAliasHead a2 []
        &&  patternHead /= getSentenceSymbolOrAliasHead a4 []
        &&  patternHead /= getSentenceSymbolOrAliasHead a5 []
        &&  not (isInjHead patternHead)
    isDeclaredFunctional =
            patternHead /= getSentenceSymbolOrAliasHead a3 []
        &&  patternHead /= getSentenceSymbolOrAliasHead a5 []
    isDeclaredFunction = patternHead == getSentenceSymbolOrAliasHead a5 []
    isDeclaredInjective =
        (  patternHead /= getSentenceSymbolOrAliasHead a2 []
        && patternHead /= getSentenceSymbolOrAliasHead a5 []
        )
        || isInjHead patternHead
    isSortInjection = isInjHead patternHead

tools :: SmtMetadataTools StepperAttributes
tools = MetadataTools
    { symAttributes = mockStepperAttributes
    , symbolOrAliasType = const HeadType.Symbol
    , sortAttributes = undefined
    , isSubsortOf = const $ const False
    , subsorts = Set.singleton
    , applicationSorts = undefined
    , smtData = undefined
    }

unificationProblem
    :: UnificationTerm
    -> UnificationTerm
    -> TermLike Variable
unificationProblem (UnificationTerm term1) (UnificationTerm term2) =
    mkAnd term1 term2

type Substitution = [(Text, TermLike Variable)]

unificationSubstitution
    :: Substitution
    -> [ (Variable, TermLike Variable) ]
unificationSubstitution = map trans
  where
    trans (v, p) =
        ( Variable
            { variableSort = termLikeSort p
            , variableName = testId v
            , variableCounter = mempty
            }
        , p
        )

unificationResult :: UnificationResult -> Pattern Variable
unificationResult
    UnificationResult { term, substitution, predicate }
  =
    Conditional
        { term
        , predicate
        , substitution =
            Substitution.unsafeWrap $ unificationSubstitution substitution
        }

newtype UnificationTerm = UnificationTerm (TermLike Variable)
data UnificationResult =
    UnificationResult
        { term :: TermLike Variable
        , substitution :: Substitution
        , predicate :: Syntax.Predicate Variable
        }

andSimplifySuccess
    :: HasCallStack
    => UnificationTerm
    -> UnificationTerm
    -> [UnificationResult]
    -> Assertion
andSimplifySuccess term1 term2 results = do
    let expect = map unificationResult results
    Right subst' <-
        runSMT
        $ evalSimplifier emptyLogger
        $ Monad.Unify.runUnifier
        $ simplifyAnds
            tools
            (Mock.substitutionSimplifier tools)
            (Simplifier.create tools Map.empty)
            Map.empty
            (unificationProblem term1 term2 :| [])
    assertEqualWithExplanation "" expect subst'

andSimplifyFailure
    :: HasCallStack
    => UnificationTerm
    -> UnificationTerm
    -> UnificationError
    -> Assertion
andSimplifyFailure term1 term2 err = do
    let expect :: Either UnificationOrSubstitutionError (Pattern Variable)
        expect = Left (UnificationError err)
    actual <-
        runSMT
        $ evalSimplifier emptyLogger
        $ Monad.Unify.runUnifier
        $ simplifyAnds
            tools
            (Mock.substitutionSimplifier tools)
            (Simplifier.create tools Map.empty)
            Map.empty
            (unificationProblem term1 term2 :| [])
    assertEqual "" (show expect) (show actual)

andSimplifyException
    :: HasCallStack
    => String
    -> UnificationTerm
    -> UnificationTerm
    -> String
    -> TestTree
andSimplifyException message term1 term2 exceptionMessage =
    testCase
        message
        ( catch test handler )
    where
        test = do
            var <-
                runSMT
                $ evalSimplifier emptyLogger
                $ Monad.Unify.runUnifier
                $ simplifyAnds
                    tools
                    (Mock.substitutionSimplifier tools)
                    (Simplifier.create tools Map.empty)
                    Map.empty
                    (unificationProblem term1 term2 :| [])
            _ <- evaluate var
            assertFailure "This evaluation should fail"
        handler (ErrorCall s) =
            assertEqual ""
                exceptionMessage
                s

unificationProcedureSuccessWithSimplifiers
    :: HasCallStack
    => TestName
    -> SmtMetadataTools StepperAttributes
    -- TODO(virgil): The above should not be here, we should just be using
    -- `mockMetadataTools`, but while we are also using 'tools' below,
    -- not passing it explicitly might be too confusing.
    -> BuiltinAndAxiomSimplifierMap
    -> UnificationTerm
    -> UnificationTerm
    -> [([(Variable, TermLike Variable)], Syntax.Predicate Variable)]
    -> TestTree
unificationProcedureSuccessWithSimplifiers
    message
    mockTools
    axiomIdToSimplifier
    (UnificationTerm term1)
    (UnificationTerm term2)
    expect
  =
    testCase message $ do
        Right results <-
            runSMT
            $ evalSimplifier emptyLogger
            $ Monad.Unify.runUnifier
            $ unificationProcedure
                mockTools
                (Mock.substitutionSimplifier tools)
                (Simplifier.create tools axiomIdToSimplifier)
                axiomIdToSimplifier
                term1
                term2
        let
            normalize
                :: Predicate Variable
                -> ([(Variable, TermLike Variable)], Syntax.Predicate Variable)
            normalize Conditional { substitution, predicate } =
                (Substitution.unwrap substitution, predicate)
        assertEqualWithExplanation ""
            expect
            (map normalize results)

unificationProcedureSuccess
    :: HasCallStack
    => TestName
    -> UnificationTerm
    -> UnificationTerm
    -> [(Substitution, Syntax.Predicate Variable)]
    -> TestTree
unificationProcedureSuccess message term1 term2 substPredicate =
    unificationProcedureSuccessWithSimplifiers
        message
        tools
        Map.empty
        term1
        term2
        expect
  where
    expect =
        map (Bifunctor.first unificationSubstitution) substPredicate

test_unification :: [TestTree]
test_unification =
    [ testCase "Constant" $
        andSimplifySuccess
            (UnificationTerm aA)
            (UnificationTerm aA)
            [ UnificationResult
                { term = aA
                , substitution = []
                , predicate = Syntax.Predicate.makeTruePredicate
                }
            ]
    , testCase "Variable" $
        andSimplifySuccess
            (UnificationTerm x)
            (UnificationTerm aA)
            [ UnificationResult
                { term = aA
                , substitution = [("x", aA)]
                , predicate = Syntax.Predicate.makeTruePredicate
                }
            ]
    , testCase "one level" $
        andSimplifySuccess
            (UnificationTerm (applySymbol_ f [x]))
            (UnificationTerm (applySymbol_ f [aA]))
            [ UnificationResult
                { term = applySymbol_ f [aA]
                , substitution = [("x", aA)]
                , predicate = Syntax.Predicate.makeTruePredicate
                }
            ]
    , testCase "equal non-constructor patterns" $
        andSimplifySuccess
            (UnificationTerm a2A)
            (UnificationTerm a2A)
            [ UnificationResult
                { term = a2A
                , substitution = []
                , predicate = Syntax.Predicate.makeTruePredicate
                }
            ]
    , testCase "variable + non-constructor pattern" $
        andSimplifySuccess
            (UnificationTerm a2A)
            (UnificationTerm x)
            [ UnificationResult
                { term = a2A
                , substitution = [("x", a2A)]
                , predicate = Syntax.Predicate.makeTruePredicate
                }
            ]
    , testCase "https://basics.sjtu.edu.cn/seminars/c_chu/Algorithm.pdf slide 3" $
        andSimplifySuccess
            (UnificationTerm
                (applySymbol_ ef [ex1, applySymbol_ eh [ex1], ex2])
            )
            (UnificationTerm
                (applySymbol_ ef [applySymbol_ eg [ex3], ex4, ex3])
            )
            [ UnificationResult
                { term = applySymbol_
                    ef
                    [ applySymbol_ eg [ex3]
                    , applySymbol_ eh [ex1]
                    , ex3
                    ]
                , substitution =
                    [ ("ex1", applySymbol_ eg [ex3])
                    , ("ex2", ex3)
                    , ("ex4", applySymbol_ eh [applySymbol_ eg [ex3]])
                    ]
                , predicate = Syntax.Predicate.makeTruePredicate
                }
            ]
    , testCase "f(g(X),X) = f(Y,a) https://en.wikipedia.org/wiki/Unification_(computer_science)#Examples_of_syntactic_unification_of_first-order_terms" $
        andSimplifySuccess

            (UnificationTerm
                (applySymbol_ nonLinF [applySymbol_ nonLinG [nonLinX], nonLinX])
            )
            (UnificationTerm (applySymbol_ nonLinF [nonLinY, nonLinA]))
            [ UnificationResult
                { term = applySymbol_
                    nonLinF
                    [applySymbol_ nonLinG [nonLinX], nonLinA]
                , substitution =
                    [ ("x", nonLinA)
                    , ("y", applySymbol_ nonLinG [nonLinA])
                    ]
                , predicate = Syntax.Predicate.makeTruePredicate
                }
            ]
    , testCase "times(times(a, y), x) = times(x, times(y, a))" $
        andSimplifySuccess
            (UnificationTerm
                (applySymbol_ expBin [applySymbol_ expBin [expA, expY], expX])
            )
            (UnificationTerm
                (applySymbol_ expBin [expX, applySymbol_ expBin [expY, expA]])
            )
            [ UnificationResult
                { term = applySymbol_
                    expBin
                    [ applySymbol_ expBin [expA, expY]
                    , applySymbol_ expBin [expY, expA]
                    ]
                , substitution =
                    [ ("a", expY)
                    , ("x", applySymbol_ expBin [expY, expY])
                    ]
                , predicate = Syntax.Predicate.makeTruePredicate
                }
            ]
    , unificationProcedureSuccess
        "times(x, g(x)) = times(a, a) -- cycle bottom"
        (UnificationTerm (applySymbol_ expBin [expX, applySymbol_ eg [expX]]))
        (UnificationTerm (applySymbol_ expBin [expA, expA]))
        []
    , unificationProcedureSuccess
        "times(times(a, y), x) = times(x, times(y, a))"
        (UnificationTerm
            (applySymbol_ expBin [applySymbol_ expBin [expA, expY], expX])
        )
        (UnificationTerm
            (applySymbol_ expBin [expX, applySymbol_ expBin [expY, expA]])
        )
        [   (   [ ("a", expY)
                , ("x", applySymbol_ expBin [expY, expY])
                ]
            , Syntax.Predicate.makeTruePredicate
            )
        ]
    , unificationProcedureSuccess
        "Unifying two non-ctors results in equals predicate"
        (UnificationTerm a2A)
        (UnificationTerm a4A)
        [ ([], makeEqualsPredicate a2A a4A) ]
    , unificationProcedureSuccess
        "Unifying function and variable results in ceil predicate"
        (UnificationTerm x)
        (UnificationTerm a5A)
        [   ( [("x", a5A)]
            , Syntax.Predicate.makeCeilPredicate a5A
            )
        ]
    , testGroup "inj unification tests" injUnificationTests
    , testCase "Unmatching constants is bottom" $
        andSimplifySuccess
            (UnificationTerm aA)
            (UnificationTerm a1A)
            []
    , testCase "Unmatching domain values is bottom" $
        andSimplifySuccess
            (UnificationTerm dv1)
            (UnificationTerm dv2)
            []
    , andSimplifyException "Unmatching constructor constant + domain value"
        (UnificationTerm aA)
        (UnificationTerm dv2)
        "Cannot handle Constructor and DomainValue:\n\
        \a{}()\n\\dv{s1{}}(\"dv2\")\n"
    , andSimplifyException "Unmatching domain value + constructor constant"
        (UnificationTerm dv1)
        (UnificationTerm aA)
        "Cannot handle DomainValue and Constructor:\n\
        \\\dv{s1{}}(\"dv1\")\na{}()\n"
    , testCase "Unmatching domain value + nonconstructor constant" $
        andSimplifySuccess
            (UnificationTerm dv1)
            (UnificationTerm a2A)
            [ UnificationResult
                { term = dv1
                , substitution = []
                , predicate = makeEqualsPredicate dv1 a2A
                }
            ]
    , testCase "Unmatching nonconstructor constant + domain value" $
        andSimplifySuccess
            (UnificationTerm a2A)
            (UnificationTerm dv1)
            [ UnificationResult
                { term = a2A
                , substitution = []
                , predicate = makeEqualsPredicate a2A dv1
                }
            ]
    , testCase "non-functional pattern" $
        andSimplifyFailure
            (UnificationTerm x)
            (UnificationTerm a3A)
            (unsupportedPatterns
                "Unknown unification case."
                x
                a3A
            )
    , testCase "non-constructor symbolHead right" $
        andSimplifySuccess
            (UnificationTerm aA)
            (UnificationTerm a2A)
            [ UnificationResult
                { term = aA
                , substitution = []
                , predicate = makeEqualsPredicate aA a2A
                }
            ]
    , testCase "non-constructor symbolHead left" $
        andSimplifySuccess
            (UnificationTerm a2A)
            (UnificationTerm aA)
            [ UnificationResult
                { term = a2A
                , substitution = []
                , predicate = makeEqualsPredicate a2A aA
                }
            ]
    , testCase "nested a=a1 is bottom" $
        andSimplifySuccess
            (UnificationTerm (applySymbol_ f [aA]))
            (UnificationTerm (applySymbol_ f [a1A]))
            []
          {- currently this cannot even be built because of builder checks
    , andSimplifyFailure "Unmatching sorts"
        (UnificationTerm aA)
        (UnificationTerm bA)
        UnificationError
        -}
    , testCase "Maps substitution variables"
        (assertEqualWithExplanation ""
            [(W "1", war' "2")]
            (Substitution.unwrap
                . Substitution.mapVariables showVar
                . Substitution.wrap
                $ [(V 1, var' 2)]
            )
        )

    ]

test_unsupportedConstructs :: TestTree
test_unsupportedConstructs =
    testCase "Unsupported constructs" $
        andSimplifyFailure
            (UnificationTerm (applySymbol_ f [aA]))
            (UnificationTerm (applySymbol_ f [mkImplies aA (mkNext a1A)]))
            (unsupportedPatterns
                "Unknown unification case."
                aA
                (mkImplies aA (mkNext a1A))
            )

newtype V = V Integer
    deriving (Show, Eq, Ord)

newtype W = W String
    deriving (Show, Eq, Ord)

instance SortedVariable V where
    sortedVariableSort _ = sortVar
    fromVariable = error "Not implemented"
    toVariable = error "Not implemented"

instance SortedVariable W where
    sortedVariableSort _ = sortVar
    fromVariable = error "Not implemented"
    toVariable = error "Not implemented"

instance EqualWithExplanation V where
    compareWithExplanation = rawCompareWithExplanation
    printWithExplanation = show

instance EqualWithExplanation W where
    compareWithExplanation = rawCompareWithExplanation
    printWithExplanation = show

showVar :: V -> W
showVar (V i) = W (show i)

var' :: Integer -> TermLike V
var' i = mkVar (V i)

war' :: String -> TermLike W
war' s = mkVar (W s)

sortVar :: Sort
sortVar = SortVariableSort (SortVariable (Id "#a" AstLocationTest))

injUnificationTests :: [TestTree]
injUnificationTests =
    [ testCase "Injected Variable" $
        andSimplifySuccess
            (UnificationTerm (applyInj s2 x))
            (UnificationTerm (applyInj s2 aA))
            [ UnificationResult
                { term = applyInj s2 aA
                , substitution = [("x", aA)]
                , predicate = Syntax.Predicate.makeTruePredicate
                }
            ]
    , testCase "Variable" $
        andSimplifySuccess
            (UnificationTerm xs2)
            (UnificationTerm (applyInj s2 aA))
            [ UnificationResult
                { term = applyInj s2 aA
                , substitution = [("xs2", applyInj s2 aA)]
                , predicate = Syntax.Predicate.makeTruePredicate
                }
            ]
    , testCase "Injected Variable vs doubly injected term" $ do
        term2 <-
            simplifyPattern
            $ UnificationTerm (applyInj s2 (applyInj s3 aA))
        andSimplifySuccess
            (UnificationTerm (applyInj s2 x))
            term2
            [ UnificationResult
                { term = applyInj s2 aA
                , substitution = [("x", aA)]
                , predicate = Syntax.Predicate.makeTruePredicate
                }
            ]
    , testCase "doubly injected variable vs injected term" $ do
        term1 <-
            simplifyPattern
            $ UnificationTerm (applyInj s2 (applyInj s3 x))
        andSimplifySuccess
            term1
            (UnificationTerm (applyInj s2 aA))
            [ UnificationResult
                { term = applyInj s2 aA
                , substitution = [("x", aA)]
                , predicate = Syntax.Predicate.makeTruePredicate
                }
            ]
    , testCase "doubly injected variable vs doubly injected term" $ do
        term1 <-
            simplifyPattern
            $ UnificationTerm (applyInj s2 (applyInj s4 x))
        term2 <-
            simplifyPattern
            $ UnificationTerm (applyInj s2 (applyInj s3 aA))
        andSimplifySuccess
            term1
            term2
            [ UnificationResult
                { term = applyInj s2 aA
                , substitution = [("x", aA)]
                , predicate = Syntax.Predicate.makeTruePredicate
                }
            ]
    , testCase "constant vs injection is bottom" $
        andSimplifySuccess
            (UnificationTerm aA)
            (UnificationTerm (applyInj s1 xs2))
            []
    , testCase "unmatching nested injections" $ do
        term1 <-
            simplifyPattern
            $ UnificationTerm (applyInj s4 (applyInj s2 aA))
        term2 <-
            simplifyPattern
            $ UnificationTerm (applyInj s4 (applyInj s3 bA))
        andSimplifySuccess
            term1
            term2
            []
    , testCase "unmatching injections" $
        andSimplifySuccess
            -- TODO(traiansf): this should succeed if s1 < s2 < s3
            (UnificationTerm (applyInj s3 aA))
            (UnificationTerm (applyInj s3 xs2))
            []
    ]

simplifyPattern :: UnificationTerm -> IO UnificationTerm
simplifyPattern (UnificationTerm term) = do
    Conditional { term = term' } <- runSMT $ evalSimplifier emptyLogger simplifier
    return $ UnificationTerm term'
  where
    simplifier = do
        simplifiedPatterns <-
            Pattern.simplify
                tools
                (Mock.substitutionSimplifier tools)
                (Simplifier.create tools functionRegistry)
                functionRegistry
                expandedPattern
        case MultiOr.extractPatterns simplifiedPatterns of
            [] -> return Pattern.bottom
            (config : _) -> return config
    functionRegistry = Map.empty
    expandedPattern = Pattern.fromTermLike term

makeEqualsPredicate
    :: TermLike Variable
    -> TermLike Variable
    -> Syntax.Predicate Variable
makeEqualsPredicate = Syntax.Predicate.makeEqualsPredicate

runSMT :: SMT a -> IO a
runSMT = SMT.runSMT SMT.defaultConfig
