Config 
  { font = "xft:inconsolata:size=10:antialias=true"
  , bgColor = "#002b36"
  , fgColor = "#657b83"
  , position = TopW L 100
  , lowerOnStart = True
  , hideOnStart = False
  , commands =
      [ Run Date        "<fc=#93a1a1>%a %b %_d %Y %H:%M</fc>" "date"  10
      , Run Com         "uname" ["-s","-r"]                   "uname" 36000
      , Run StdinReader
      ]
  , sepChar = "%"
  , alignSep = "}{"
  , template = "%StdinReader% }{ %date% %uname%"
  }