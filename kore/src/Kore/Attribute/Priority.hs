{-|
Copyright   : (c) Runtime Verification, 2019
License     : NCSA

-}
module Kore.Attribute.Priority
    ( Priority (..)
    , defaultPriority, owisePriority
    , priorityId, prioritySymbol, priorityAttribute
    ) where

import Prelude.Kore

import qualified Generics.SOP as SOP
import qualified GHC.Generics as GHC

import Kore.Attribute.Parser as Parser
import Kore.Debug

{- | @Priority@ represents the @priority@ attribute.

    It is unsafe to use this directly when handling the priorities of
    rules with a 'RulePattern' or a 'EqualityRule' representation.
    'Kore.Step.RulePattern.getPriorityOfRule'
    or 'Kore.Step.EqualityPattern.getPriorityOfRule' should be used instead.
 -}
newtype Priority = Priority { getPriority :: Maybe Integer }
    deriving (Eq, GHC.Generic, Ord, Show)

instance SOP.Generic Priority

instance SOP.HasDatatypeInfo Priority

instance Debug Priority

instance Diff Priority

instance NFData Priority

instance Default Priority where
    def = Priority Nothing

-- | Default priority for 'EqualityRule' and 'RulePattern'.
defaultPriority :: Integer
defaultPriority = 50

-- | Priority for 'EqualityRule' and 'RulePattern' with the
-- 'owise' attribute.
owisePriority :: Integer
owisePriority = 200

-- | Kore identifier representing the @priority@ attribute symbol.
priorityId :: Id
priorityId = "priority"

-- | Kore symbol representing the @priority@ attribute.
prioritySymbol :: SymbolOrAlias
prioritySymbol =
    SymbolOrAlias
        { symbolOrAliasConstructor = priorityId
        , symbolOrAliasParams = []
        }

-- | Kore pattern representing a @priority@ attribute.
priorityAttribute :: Integer -> AttributePattern
priorityAttribute name =
    attributePattern prioritySymbol [attributeInteger name]

instance ParseAttributes Priority where
    parseAttribute =
        withApplication' $ \params args (Priority priority) -> do
            Parser.getZeroParams params
            arg <- Parser.getOneArgument args
            stringLiteral <- Parser.getStringLiteral arg
            integer <- Parser.parseInteger stringLiteral
            unless (isNothing priority) failDuplicate'
            return Priority { getPriority = Just integer }
      where
        withApplication' = Parser.withApplication priorityId
        failDuplicate' = Parser.failDuplicate priorityId

instance From Priority Attributes where
    from =
        maybe def toAttribute . getPriority
      where
        toAttribute = from @AttributePattern . priorityAttribute
