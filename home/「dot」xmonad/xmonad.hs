import XMonad
import Solarized
import qualified XMonad.StackSet as W
import XMonad.Hooks.ManageHelpers (doRectFloat, doCenterFloat)

main = do
  xmonad defaultConfig {
      modMask = mod4Mask -- super key
    , terminal = "Terminal"
    , normalBorderColor = solarizedBase01
    , focusedBorderColor = solarizedRed
    , manageHook = composeAll [
                           --   appName   =? "git-gui"    --> doRectFloat(W.RationalRect 0.05 0.05 0.9 0.9)
                                appName   =? "gitk"       --> doRectFloat(W.RationalRect 0.05 0.05 0.9 0.9)
                              , className =? "keepassx"   --> doRectFloat(W.RationalRect 0.05 0.05 0.9 0.9)
                              , appName   =? "push_setup" --> doRectFloat(W.RationalRect 0.05 0.05 0.9 0.9)
      ]
  }