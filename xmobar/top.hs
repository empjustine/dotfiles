Config
  { bgColor = "#002b36"
  , fgColor = "#657b83"
  , commands =
      [ Run Date        "%j W%V-%u %Y-%m-%dT%H:%M:%S%Z%z" "date" 10
      , Run StdinReader
      ]
  , template = "%StdinReader% }{ %date%"
  }