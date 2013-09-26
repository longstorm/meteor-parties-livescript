let exports = this
  locale = void
  localeJSON = { }

  getDict = -> localeJSON
  getLocale = -> locale
  getLocaleDict = -> getDict()?[getLocale()]

  getText = (translationKey) ->
    unless typeof getLocale() is 'string' and (access = getLocaleDict())?
      return null

    for key in translationKey.split '.'
      access = access[key]
      return null unless access?
    return access

  ruleMatches = (condition, value) -> switch condition
    | 'any' or 'otherwise' => yes
    | 'one'                => +value is 1
    | 'many'               => +value > 1
    | 'none'               => +value is 0
    | 'n/a'                => not value
    | 'error'              => not value?

  interpolate = (interpolatedText, args) ->
    return "i18n Error" unless interpolatedText
    argCount = 0
    while (match = interpolatedText.match /[A-Z$]{[^}]*}/)?
      before = interpolatedText.substring 0, match.index
      after = interpolatedText.substring (match.index + match[0].length)

      if argCount < args.length
        interpolatedText = "#before#{args[argCount++]}#after"
      # if we don't get enough arguments, instead of returning the parsed
      # string, return a curried function that takes the remaining args.
      else return (...moreArgs) -> interpolate interpolatedText, moreArgs
    return interpolatedText

  i18n = (translationKey, ...args) ->
    return interpolate (getText translationKey), args

  inflect = (rules, number) ->
    for rule in rules
      separator = rule.indexOf ':'
      [cond, text] = [rule.substring(0, separator), rule.substr separator + 2]
      return interpolate text, [number] if ruleMatches cond, number

  i18n.inflect = (translationKey, number) ->
    rules = getText translationKey
    if arguments.length > 1 then inflect rules, number
    else (arg) -> inflect rules, arg

  onReady = []
  chainableActions =
    getLocale: -> getLocale
    getDict: -> getDict
    getLocaleDict: -> getLocaleDict

    addLocaleDict: (json) ->
      localeJSON[lang] = dict for own lang, dict of (JSON.parse json)

    setLocale: (loc) ->
      locale := loc
      return this

    setDict: (dict) ->
      localeJSON := dict
      return this

    set: (object) ->
      locale := object.locale if object.locale?
      localeJSON := object.dict if object.dict?
      return this

    ready: ->
      readyCallback() for readyCallback in onReady
      onReady := []
      return this

    onReady:
      addListener: (cb) ->
        onReady.push cb
        return this

      removeListener: (cb) ->
        for readyCallback, i in onReady when readyCallback is cb
          onReady.splice i, 1
          break
        return this

      clearListeners: ->
        onReady := []
        return this

  _.extend i18n, chainableActions

  exports.i18n = i18n
  exports.error = (
