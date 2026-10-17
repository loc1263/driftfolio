type
  Quote* = object
    ticker*: string
    url*: string
    ret1m*, ret3m*, ret6m*, score*: float
    price*, sma50*: float
    aboveSma50*: bool
