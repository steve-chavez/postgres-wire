module Connection where

import Control.Exception (bracket)
import Database.PostgreSQL.Driver.Connection
import Database.PostgreSQL.Driver.Settings

-- | Creates connection with default filter.
withConnection :: (Connection -> IO a) -> IO a
withConnection = bracket (getConnection <$> connect defaultSettings) close

-- | Creates connection than collects all server messages in chan.
withConnectionAll :: (Connection -> IO a) -> IO a
withConnectionAll = bracket
    (getConnection <$> connectWith defaultSettings filterAllowedAll) close

defaultSettings = defaultConnectionSettings
    { settingsHost     = "localhost"
    , settingsDatabase = "travis_test"
    , settingsUser     = "postgres"
    , settingsPassword = ""
    }

getConnection :: Either Error Connection -> Connection
getConnection (Left e) = error $ "Connection error " ++ show e
getConnection (Right c) = c

