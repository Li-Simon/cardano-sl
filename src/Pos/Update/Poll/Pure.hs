-- | Pure Poll

module Pos.Update.Poll.Pure
       ( PurePoll (..)
       ) where

import           Universum                  hiding (toList)
import qualified Universum                  (toList)

import           Control.Lens               (to, (%=), (.=))
import qualified Data.HashMap.Strict        as HM
import           System.Wlog                (CanLog, HasLoggerName, NamedPureLogger)

import           Pos.Update.Poll.Class      (MonadPoll (..), MonadPollRead (..))
import qualified Pos.Update.Poll.PollState  as Poll
import           Pos.Update.Poll.Types      (DecidedProposalState (dpsDifficulty),
                                             ProposalState (..),
                                             UndecidedProposalState (upsSlot))
import           Pos.Util.Modifier          (delete, insert, lookup, keys, toList, values)

newtype PurePoll a = PurePoll
    { getPurePoll :: NamedPureLogger (State Poll.PollState) a
    } deriving (Functor, Applicative, Monad, CanLog, HasLoggerName)

instance MonadPollRead PurePoll where
    getBVState bv = PurePoll $ use $ Poll.psBlockVersions . to (lookup (const Nothing) bv)
    getProposedBVs = PurePoll $ use $ Poll.psBlockVersions . to (keys [])
    getEpochProposers = PurePoll $ use $ Poll.psEpochProposers
    getConfirmedBVStates = PurePoll $ use $ Poll.psBlockVersions . to (toList [])
    getAdoptedBVFull = PurePoll $ use $ Poll.psAdoptedBV
    getLastConfirmedSV an =
        PurePoll $ use $ Poll.psConfirmedBVs . to (lookup (const Nothing) an)
    getProposal ui =
        PurePoll $ use $ Poll.psActiveProposals . to (lookup (const Nothing) ui)
    getProposalsByApp an = PurePoll $ do
        delActiveProposalsIndices <- use Poll.psDelActivePropsIdx
        activeProposals           <- use Poll.psActiveProposals
        pure $ propGetByApp delActiveProposalsIndices activeProposals
      where propGetByApp appHashmap upIdHashmap = fromMaybe [] $
                do hashset <- HM.lookup an appHashmap
                   let uidList = Universum.toList hashset
                       propStateList =
                           fmap (flip (lookup (const Nothing)) upIdHashmap) uidList
                   sequence propStateList
    getConfirmedProposals = PurePoll $ use $ Poll.psConfirmedProposals . to (values [])
    getEpochTotalStake ei = PurePoll $ use $ Poll.psStakePerEpoch . to (HM.lookup ei)
    getRichmanStake ei si =
        PurePoll $ use $ Poll.psMultiRichmenStake . to (HM.lookup ei >=> HM.lookup si)
    getOldProposals si =
        PurePoll $ use $ Poll.psUndecidedProposals . to (filter ((<= si) . upsSlot))
    getDeepProposals cd =
        PurePoll $ use $ Poll.psDecidedProposals .
            to (filter ((> (Just cd)) . dpsDifficulty))
    getBlockIssuerStake ei si =
        PurePoll $ use $ Poll.psIssuersStakes . to (HM.lookup ei >=> HM.lookup si)
    getSlottingData = PurePoll $ use Poll.psSlottingData

instance MonadPoll PurePoll where
    putBVState bv bvs = PurePoll $ Poll.psBlockVersions %= insert bv bvs
    delBVState bv = PurePoll $ Poll.psBlockVersions %= delete bv
    setAdoptedBV bv = PurePoll $ Poll.psAdoptedBV %= (_1 .~ bv)
    setLastConfirmedSV sv = PurePoll $ Poll.psSoftwareVersion .= sv
    delConfirmedSV an = PurePoll $ Poll.psConfirmedBVs %= delete an
    addConfirmedProposal cps = PurePoll $ void $ do
        addProp <$> use Poll.psSoftwareVersion <*> use Poll.psConfirmedProposals
      where
        addProp sv svMap = insert sv cps svMap
    delConfirmedProposal sv = PurePoll $ Poll.psConfirmedProposals %= delete sv
    insertActiveProposal p = PurePoll $ void $ do
        decideProp <$> use Poll.psDecidedProposals
      where
          decideProp = case p of
              PSDecided ps -> (ps :)
              _ -> identity
    deactivateProposal ui = PurePoll $ Poll.psActiveProposals %= delete ui
    setSlottingData sd = PurePoll $ Poll.psSlottingData .= sd
    setEpochProposers hs = PurePoll $ Poll.psEpochProposers .= hs
