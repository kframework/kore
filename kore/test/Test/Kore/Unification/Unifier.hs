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
import qualified Control.Lens as Lens
import qualified Data.Bifunctor as Bifunctor
import           Data.Function
import           Data.List.NonEmpty
                 ( NonEmpty ((:|)) )
import           Data.Map
                 ( Map )
import qualified Data.Map as Map
import           Data.Maybe
import qualified Data.Set as Set
import           Data.Text
                 ( Text )

import           Kore.Attribute.Constructor
import           Kore.Attribute.Function
import           Kore.Attribute.Functional
import           Kore.Attribute.Injective
import           Kore.Attribute.SortInjection
import qualified Kore.Attribute.Symbol as Attribute
import           Kore.IndexedModule.MetadataTools hiding
                 ( HeadType (..) )
import qualified Kore.IndexedModule.MetadataTools as HeadType
                 ( HeadType (..) )
import qualified Kore.Internal.MultiOr as MultiOr
import           Kore.Internal.Pattern as Pattern
import           Kore.Internal.Symbol
import           Kore.Internal.TermLike hiding
                 ( V )
import qualified Kore.Predicate.Predicate as Syntax.Predicate
import qualified Kore.Predicate.Predicate as Syntax
                 ( Predicate )
import           Kore.Step.Simplification.Data
                 ( BuiltinAndAxiomSimplifierMap )
import           Kore.Step.Simplification.Data
                 ( Env (..), evalSimplifier )
import qualified Kore.Step.Simplification.Pattern as Pattern
import           Kore.Syntax.Sentence
                 ( SentenceSymbol, SentenceSymbolOrAlias (..) )
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
import qualified Test.Kore.Step.MockSymbols as Mock

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

constructor :: Symbol -> Symbol
constructor =
    Lens.set
        (lensSymbolAttributes . Attribute.lensConstructor)
        Attribute.Constructor { isConstructor = True }

functional :: Symbol -> Symbol
functional =
    Lens.set
        (lensSymbolAttributes . Attribute.lensFunctional)
        Attribute.Functional { isDeclaredFunctional = True }

function :: Symbol -> Symbol
function =
    Lens.set
        (lensSymbolAttributes . Attribute.lensFunction)
        Attribute.Function { isDeclaredFunction = True }

injective :: Symbol -> Symbol
injective =
    Lens.set
        (lensSymbolAttributes . Attribute.lensInjective)
        Attribute.Injective { isDeclaredInjective = True }

sortInjection :: Symbol -> Symbol
sortInjection =
    Lens.set
        (lensSymbolAttributes . Attribute.lensSortInjection)
        Attribute.SortInjection { isSortInjection = True }

symbol :: Text -> Symbol
symbol name =
    Symbol
        { symbolConstructor = testId name
        , symbolParams = []
        , symbolAttributes = Attribute.defaultSymbolAttributes
        }

var :: Text -> Sort -> Variable
var name variableSort =
    Variable
        { variableName = testId name
        , variableSort
        , variableCounter = mempty
        }

a1Symbol, a2Symbol, a3Symbol, a4Symbol, a5Symbol :: Symbol
a1Symbol = symbol "a1"
a2Symbol = symbol "a2"
a3Symbol = symbol "a3"
a4Symbol = symbol "a4"
a5Symbol = symbol "a5"

a1, a2, a3, a4, a5 :: TermLike Variable
a1 = mkApplySymbol s1 a1Symbol []
a2 = mkApplySymbol s1 a2Symbol []
a3 = mkApplySymbol s1 a3Symbol []
a4 = mkApplySymbol s1 a4Symbol []
a5 = mkApplySymbol s1 a5Symbol []

aSymbol, bSymbol, fSymbol :: Symbol
aSymbol = symbol "a"
bSymbol = symbol "b"
fSymbol = symbol "f"

a, b :: TermLike Variable
a = mkApplySymbol s1 aSymbol []
b = mkApplySymbol s2 bSymbol []

f :: TermLike Variable -> TermLike Variable
f x = mkApplySymbol s2 fSymbol [x]

efSymbol, egSymbol, ehSymbol :: SentenceSymbol (TermLike Variable)
efSymbol = symbol "ef"
egSymbol = symbol "eg"
ehSymbol = symbol "eh"

ef
    :: TermLike Variable
    -> TermLike Variable
    -> TermLike Variable
    -> TermLike Variable
ef x y z = mkApplySymbol s1 efSymbol [x, y, z]

eg, eh :: TermLike Variable -> TermLike Variable
eg x = mkApplySymbol s1 egSymbol [x]
eh x = mkApplySymbol s1 ehSymbol [x]

nonLinFSymbol, nonLinGSymbol, nonLinASymbol, nonLinASSymbol :: Symbol
nonLinFSymbol = symbol "nonLinF"
nonLinGSymbol = symbol "nonLinG"
nonLinASymbol = symbol "nonLinA"
nonLinASSymbol = symbol "nonLinA"

nonLinF :: TermLike Variable -> TermLike Variable -> TermLike Variable
nonLinF x y = mkApplySymbol s1 nonLinFSymbol [x, y]

nonLinG :: TermLike Variable -> TermLike Variable
nonLinG x = mkApplySymbol s1 nonLinGSymbol [x]

nonLinAS :: TermLike Variable
nonLinAS = mkApplySymbol s1 nonLinASymbol []

nonLinA, nonLinX, nonLinY :: TermLike Variable
nonLinA = mkApplySymbol s1 nonLinASSymbol []
nonLinX = mkVar $ var "x" s1
nonLinY = mkVar $ var "y" s1

expBin :: SentenceSymbol (TermLike Variable)
expBin = mkSymbol_ (testId "times") [s1, s1] s1

expA, expX, expY :: TermLike Variable
expA = mkVar $ var "a" s1
expX = mkVar $ var "x" s1
expY = mkVar $ var "y" s1

ex1, ex2, ex3, ex4 :: TermLike Variable
ex1 = mkVar $ var "ex1" s1
ex2 = mkVar $ var "ex2" s1
ex3 = mkVar $ var "ex3" s1
ex4 = mkVar $ var "ex4" s1


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

bA :: TermLike Variable
bA = applySymbol_ b []

x :: TermLike Variable
x = mkVar $ var "x" s1

xs2 :: TermLike Variable
xs2 = mkVar $ var "xs2" s2

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

symbols :: [Symbol]
symbols = []

symbolAttributesMap :: Map SymbolOrAlias Attribute.Symbol
symbolAttributesMap =
    Map.fromList $ map ((,) <$> toSymbolOrAlias <*> symbolAttributes) symbols

mockStepperAttributes :: SymbolOrAlias -> Attribute.Symbol
mockStepperAttributes patternHead =
    Map.lookup patternHead symbolAttributesMap
    & fromMaybe Attribute.defaultSymbolAttributes
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

tools :: SmtMetadataTools Attribute.Symbol
tools = MetadataTools
    { symAttributes = mockStepperAttributes
    , symbolOrAliasType = const HeadType.Symbol
    , sortAttributes = undefined
    , isSubsortOf = const $ const False
    , subsorts = Set.singleton
    , applicationSorts = undefined
    , smtData = undefined
    }

testEnv :: Env
testEnv =
    Mock.env
        { metadataTools = tools
        , simplifierPredicate = Mock.substitutionSimplifier
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
        $ evalSimplifier testEnv
        $ Monad.Unify.runUnifier
        $ simplifyAnds (unificationProblem term1 term2 :| [])
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
        $ evalSimplifier testEnv
        $ Monad.Unify.runUnifier
        $ simplifyAnds (unificationProblem term1 term2 :| [])
    assertEqual "" (show expect) (show actual)

andSimplifyException
    :: HasCallStack
    => String
    -> UnificationTerm
    -> UnificationTerm
    -> String
    -> TestTree
andSimplifyException message term1 term2 exceptionMessage =
    testCase message (catch test handler)
    where
        test = do
            var <-
                runSMT $ evalSimplifier testEnv
                $ Monad.Unify.runUnifier
                $ simplifyAnds (unificationProblem term1 term2 :| [])
            _ <- evaluate var
            assertFailure "This evaluation should fail"
        handler (ErrorCall s) = assertEqual "" exceptionMessage s

unificationProcedureSuccessWithSimplifiers
    :: HasCallStack
    => TestName
    -> BuiltinAndAxiomSimplifierMap
    -> UnificationTerm
    -> UnificationTerm
    -> [([(Variable, TermLike Variable)], Syntax.Predicate Variable)]
    -> TestTree
unificationProcedureSuccessWithSimplifiers
    message
    axiomIdToSimplifier
    (UnificationTerm term1)
    (UnificationTerm term2)
    expect
  =
    testCase message $ do
        let mockEnv = testEnv { simplifierAxioms = axiomIdToSimplifier }
        Right results <-
            runSMT
            $ evalSimplifier mockEnv
            $ Monad.Unify.runUnifier
            $ unificationProcedure term1 term2
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
            (UnificationTerm a)
            (UnificationTerm a)
            [ UnificationResult
                { term = a
                , substitution = []
                , predicate = Syntax.Predicate.makeTruePredicate
                }
            ]
    , testCase "Variable" $
        andSimplifySuccess
            (UnificationTerm x)
            (UnificationTerm a)
            [ UnificationResult
                { term = a
                , substitution = [("x", a)]
                , predicate = Syntax.Predicate.makeTruePredicate
                }
            ]
    , testCase "one level" $
        andSimplifySuccess
            (UnificationTerm (f x))
            (UnificationTerm (f a))
            [ UnificationResult
                { term = f a
                , substitution = [("x", a)]
                , predicate = Syntax.Predicate.makeTruePredicate
                }
            ]
    , testCase "equal non-constructor patterns" $
        andSimplifySuccess
            (UnificationTerm a2)
            (UnificationTerm a2)
            [ UnificationResult
                { term = a2
                , substitution = []
                , predicate = Syntax.Predicate.makeTruePredicate
                }
            ]
    , testCase "variable + non-constructor pattern" $
        andSimplifySuccess
            (UnificationTerm a2)
            (UnificationTerm x)
            [ UnificationResult
                { term = a2
                , substitution = [("x", a2)]
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
    Conditional { term = term' } <- runSMT $ evalSimplifier testEnv simplifier
    return $ UnificationTerm term'
  where
    simplifier = do
        simplifiedPatterns <- Pattern.simplify expandedPattern
        case MultiOr.extractPatterns simplifiedPatterns of
            [] -> return Pattern.bottom
            (config : _) -> return config
    expandedPattern = Pattern.fromTermLike term

makeEqualsPredicate
    :: TermLike Variable
    -> TermLike Variable
    -> Syntax.Predicate Variable
makeEqualsPredicate = Syntax.Predicate.makeEqualsPredicate

runSMT :: SMT a -> IO a
runSMT = SMT.runSMT SMT.defaultConfig emptyLogger
