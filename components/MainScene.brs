Sub init()
    m.title = m.top.findNode("title")
    m.status = m.top.findNode("status")
    m.stationList = m.top.findNode("stationList")
    m.stationList.observeField("itemSelected", "onStationSelected")
    m.upNextList = m.top.findNode("upNextList")
    m.upNextList.observeField("itemSelected", "onEpisodeSelected")
    m.nowPlaying  = m.top.findNode("nowPlaying")
    m.detailScreen = m.top.findNode("detailScreen")
    m.mode = "boot"
    m.top.setFocus(true)

    ' Device ID for Pocket Casts sync
    devReg = CreateObject("roRegistrySection", "device")
    m.deviceId = devReg.Read("pc_device_id")
    if m.deviceId = invalid or m.deviceId = ""
        m.deviceId = CreateObject("roDeviceInfo").GetChannelClientId()
        devReg.Write("pc_device_id", m.deviceId)
        devReg.Flush()
    end if

    auth = AuthRead()
    if auth <> invalid and auth.token <> ""
        showMain(auth)
    else
        promptEmail()
    end if
End Sub

' ---- login flow (two-step keyboard, dev-prefilled) -------------------------

Sub promptEmail()
    m.mode = "login_email"
    m.expectingEmailButton = true
    dlg = CreateObject("roSGNode", "KeyboardDialog")
    dlg.title = "Pocket Casts Email"
    dlg.text = TestEmail()
    dlg.buttons = ["Next", "Cancel"]
    m.dlg = dlg
    dlg.observeField("buttonSelected", "onEmailBtn")
    m.top.dialog = dlg
End Sub

Sub onEmailBtn()
    if not m.expectingEmailButton then return
    m.expectingEmailButton = false
    if m.dlg.buttonSelected = 0
        m.email = m.dlg.text
        closeDialog()
        promptPassword()
    else
        closeDialog()
        m.status.text = "Login cancelled."
        promptEmail()
    end if
End Sub

Sub promptPassword()
    m.mode = "login_password"
    m.expectingPasswordButton = true
    dlg = CreateObject("roSGNode", "KeyboardDialog")
    dlg.title = "Pocket Casts Password"
    dlg.text = TestPassword()
    dlg.buttons = ["Log In", "Back"]
    m.dlg = dlg
    dlg.observeField("buttonSelected", "onPasswordBtn")
    m.top.dialog = dlg
End Sub

Sub onPasswordBtn()
    if not m.expectingPasswordButton then return
    m.expectingPasswordButton = false
    if m.dlg.buttonSelected = 0
        m.password = m.dlg.text
        closeDialog()
        doLogin()
    else
        closeDialog()
        promptEmail()
    end if
End Sub

Sub closeDialog()
    if m.dlg <> invalid then m.dlg.close = true
    m.top.dialog = invalid
    m.dlg = invalid
End Sub

Sub doLogin()
    m.status.text = "Logging in..."
    m.relay = CreateObject("roSGNode", "RelayTask")
    m.relay.observeField("response", "onLoginResp")
    m.relay.bodyJson = FormatJSON({ action: "login", email: m.email, password: m.password })
    m.relay.control = "RUN"
End Sub

Sub onLoginResp()
    code = m.relay.status
    if code = 401 or code = 403
        AuthClear()
        m.status.text = "Invalid credentials. Try again."
        promptPassword()
        return
    end if
    if code <> 200
        m.status.text = "Login failed (" + code.ToStr() + "). Check network and try again."
        promptEmail()
        return
    end if
    data = ParseJSON(m.relay.response)
    if data = invalid or data.token = invalid or data.token = ""
        m.status.text = "Login failed (bad response). Try again."
        promptEmail()
        return
    end if
    if data.userId = invalid or data.userId = "" or data.email = invalid or data.email = ""
        m.status.text = "Login failed (incomplete user data). Try again."
        promptEmail()
        return
    end if
    AuthWrite(data.token, data.userId, data.email)
    showMain({ token: data.token, userid: data.userId, email: data.email })
End Sub

' ---- main views ------------------------------------------------------------

Sub showMain(auth as object)
    m.mode = "main"
    m.auth = auth
    m.skipBack = 10
    m.skipFwd  = 45
    m.top.setFocus(true)
    loadSkipSettings()
    showUpNext()
End Sub

Sub loadSkipSettings()
    m.settingsTask = CreateObject("roSGNode", "RelayTask")
    m.settingsTask.observeField("response", "onSkipSettingsLoaded")
    m.settingsTask.bodyJson = FormatJSON({ action: "namedSettings", token: m.auth.token })
    m.settingsTask.control = "RUN"
End Sub

Sub onSkipSettingsLoaded()
    if m.settingsTask.status <> 200 then return
    data = ParseJSON(m.settingsTask.response)
    if data = invalid then return
    if data.skipBack <> invalid and data.skipBack > 0
        m.skipBack = CInt(data.skipBack)
    end if
    if data.skipForward <> invalid and data.skipForward > 0
        m.skipFwd = CInt(data.skipForward)
    end if
    m.nowPlaying.skipBack = m.skipBack
    m.nowPlaying.skipFwd  = m.skipFwd
    print "[MainScene] skip settings back="; m.skipBack; " fwd="; m.skipFwd
End Sub

Sub showFavorites()
    print "[MainScene] showFavorites"
    m.mode = "favorites"
    m.title.text = "PocketStreams — Favorites"
    m.status.text = "Loading..."
    m.upNextList.visible = false
    m.stationList.visible = true
    list = m.stationList.findNode("list")
    if list <> invalid then list.setFocus(true)
    loadFavorites()
End Sub

Sub showBrowse()
    m.mode = "browse"
    m.title.text = "PocketStreams — Browse"
    m.status.text = "Loading..."
    m.upNextList.visible = false
    m.stationList.visible = true
    list = m.stationList.findNode("list")
    if list <> invalid then list.setFocus(true)
    loadBrowse()
End Sub

Sub showSearch()
    m.mode = "search_prompt"
    dlg = CreateObject("roSGNode", "KeyboardDialog")
    dlg.title = "Search Stations"
    dlg.buttons = ["Search", "Cancel"]
    m.dlg = dlg
    dlg.observeField("buttonSelected", "onSearchBtn")
    dlg.observeField("wasClosed", "onSearchClosed")
    m.top.dialog = dlg
End Sub

Sub onSearchBtn()
    if m.dlg.buttonSelected = 0
        query = m.dlg.text
        closeDialog()
        doSearch(query)
    else
        closeDialog()
        showFavorites()
    end if
End Sub

Sub onSearchClosed()
    if m.mode = "search_prompt"
        showFavorites()
    end if
End Sub

Sub doSearch(query as string)
    m.mode = "search"
    m.title.text = "PocketStreams — Search"
    m.status.text = "Loading..."
    m.upNextList.visible = false
    m.stationList.visible = true
    list = m.stationList.findNode("list")
    if list <> invalid then list.setFocus(true)
    loadSearch(query)
End Sub

' ---- data loading ----------------------------------------------------------

Sub loadFavorites()
    m.http = CreateObject("roSGNode", "HttpJsonTask")
    m.http.observeField("response", "onFavoritesLoaded")
    m.http.url = SupabaseUrl() + "/rest/v1/radio_favorites?select=station_id&user_uuid=eq." + m.auth.userid
    m.http.headers = { apikey: SupabaseAnonKey(), "x-user-uuid": m.auth.userid }
    m.http.control = "RUN"
End Sub

Sub onFavoritesLoaded()
    print "[MainScene] onFavoritesLoaded status="; m.http.status
    if m.http.status <> 200
        m.status.text = "Failed to load favorites."
        return
    end if
    data = ParseJSON(m.http.response)
    print "[MainScene] favorites count="; data.count()
    if data = invalid or data.count() = 0
        m.status.text = "No favorites. Press Back for menu."
        list = m.stationList.findNode("list")
        if list <> invalid then list.content = invalid
        return
    end if
    ids = []
    for each fav in data
        ids.push(fav.station_id)
    end for
    resolveStations(ids)
End Sub

Sub resolveStations(ids as object)
    m.resolvedStations = []
    m.resolveIndex = 0
    m.resolveIds = ids
    resolveNextStation()
End Sub

Sub resolveNextStation()
    if m.resolveIndex >= m.resolveIds.count()
        showStationList(m.resolvedStations)
        return
    end if
    id = m.resolveIds[m.resolveIndex]
    m.http = CreateObject("roSGNode", "HttpJsonTask")
    m.http.observeField("response", "onStationResolved")
    m.http.url = RadioBrowserUrl() + "/stations/byuuid/" + id
    m.http.headers = { "User-Agent": "PocketRadio/1.0" }
    m.http.control = "RUN"
End Sub

Sub onStationResolved()
    if m.http.status = 200
        data = ParseJSON(m.http.response)
        if data <> invalid and data.count() > 0
            station = data[0]
            if station.name <> invalid and station.name <> "" and station.url_resolved <> invalid and station.url_resolved <> ""
                m.resolvedStations.push(station)
            end if
        end if
    end if
    m.resolveIndex = m.resolveIndex + 1
    resolveNextStation()
End Sub

Sub loadBrowse()
    m.http = CreateObject("roSGNode", "HttpJsonTask")
    m.http.observeField("response", "onBrowseLoaded")
    m.http.url = RadioBrowserUrl() + "/stations/topvote?limit=50&hidebroken=true"
    m.http.headers = { "User-Agent": "PocketRadio/1.0" }
    m.http.control = "RUN"
End Sub

Sub onBrowseLoaded()
    if m.http.status <> 200
        m.status.text = "Failed to load browse."
        return
    end if
    data = ParseJSON(m.http.response)
    if data = invalid
        m.status.text = "No stations found."
        return
    end if
    showStationList(filterStations(data))
End Sub

Sub loadSearch(query as string)
    encoded = query.Trim().Replace(" ", "%20")
    m.http = CreateObject("roSGNode", "HttpJsonTask")
    m.http.observeField("response", "onSearchLoaded")
    m.http.url = RadioBrowserUrl() + "/stations/search?name=" + encoded + "&limit=40&hidebroken=true&order=votes&reverse=true"
    m.http.headers = { "User-Agent": "PocketRadio/1.0" }
    m.http.control = "RUN"
End Sub

Sub onSearchLoaded()
    if m.http.status <> 200
        m.status.text = "Search failed."
        return
    end if
    data = ParseJSON(m.http.response)
    if data = invalid
        m.status.text = "No results."
        return
    end if
    showStationList(filterStations(data))
End Sub

Function filterStations(data as object) as object
    result = []
    for each station in data
        if station.name <> invalid and station.name <> "" and station.url_resolved <> invalid and station.url_resolved <> ""
            result.push(station)
        end if
    end for
    return result
End Function

Sub showStationList(stations as object)
    print "[MainScene] showStationList count="; stations.count()
    content = createObject("roSGNode", "ContentNode")
    for each station in stations
        child = content.createChild("ContentNode")
        child.title = station.name
        child.url = station.url_resolved
        if station.favicon <> invalid and station.favicon <> ""
            child.HDPosterUrl = station.favicon
        end if
        meta = { stationuuid: station.stationuuid }
        if station.codec <> invalid and station.codec <> ""
            meta.codec = station.codec
        end if
        if station.country <> invalid and station.country <> ""
            meta.display = station.country
        end if
        meta.streamformat = inferStreamformat(station.url_resolved, station.codec)
        child.description = FormatJSON(meta)
    end for
    list = m.stationList.findNode("list")
    if list <> invalid
        list.content = content
        list.jumpToItem = 0
        list.setFocus(true)
    end if
    if stations.count() = 0
        m.status.text = "No stations."
    else
        m.status.text = stations.count().ToStr() + " stations"
    end if
End Sub

' ---- playback --------------------------------------------------------------

Sub onStationSelected()
    index = m.stationList.itemSelected
    list = m.stationList.findNode("list")
    if list = invalid then return
    content = list.content
    if content = invalid then return
    item = content.getChild(index)
    if item = invalid then return

    if m.audio = invalid
        m.audio = m.top.createChild("Audio")
        m.audio.observeField("state", "onAudioState")
    end if
    m.audio.control = "stop"

    fmt = "mp3"
    meta = ParseJSON(item.description)
    if meta <> invalid and meta.streamformat <> invalid and meta.streamformat <> ""
        fmt = meta.streamformat
    end if
    audioContent = createObject("roSGNode", "ContentNode")
    audioContent.url = item.url
    audioContent.streamformat = fmt
    m.audio.content = audioContent
    m.audio.control = "play"

    m.status.text = "Playing: " + item.title
    m.currentStation = item
    m.currentEpisode = invalid
    isLive = (fmt <> "mp3")
    m.isCurrentlyLive = isLive
    stopTracklist()
    showNowPlaying(item.title, "", item.HDPosterUrl, isLive)
    startTracklist(item.title)
End Sub

Function inferStreamformat(url as string, codec as string) as string
    if url <> invalid and url.Instr(".m3u8") >= 0
        return "hls"
    end if
    if codec <> invalid
        c = UCase(codec)
        if c = "AAC" or c = "AAC+" or c = "HE-AAC" or c = "AACPLUS"
            return "aac"
        else if c = "HLS"
            return "hls"
        end if
    end if
    return "mp3"
End Function

' ---- up next ---------------------------------------------------------------

Sub showUpNext()
    print "[MainScene] showUpNext"
    m.mode = "up_next"
    m.title.text = "PocketStreams — Up Next"
    m.status.text = "Loading..."
    m.stationList.visible = false
    m.upNextList.visible = true
    list = m.upNextList.findNode("list")
    if list <> invalid then list.setFocus(true)
    loadUpNext()
End Sub

Sub loadUpNext()
    m.status.text = "Loading Up Next..."
    m.relay = CreateObject("roSGNode", "RelayTask")
    m.relay.observeField("response", "onUpNextLoaded")
    m.relay.bodyJson = FormatJSON({
        action: "upNext",
        token: m.auth.token,
        deviceId: m.deviceId
    })
    m.relay.control = "RUN"
End Sub

Sub onUpNextLoaded()
    if m.relay.status = 401 or m.relay.status = 403
        logout()
        return
    end if
    if m.relay.status <> 200
        m.status.text = "Failed to load Up Next. Check network."
        return
    end if
    data = ParseJSON(m.relay.response)
    if data = invalid or data.episodes = invalid
        m.status.text = "No episodes in Up Next."
        return
    end if
    showUpNextList(data.episodes)
End Sub

Sub showUpNextList(episodes as object)
    content = createObject("roSGNode", "ContentNode")
    for each ep in episodes
        child = content.createChild("ContentNode")
        child.title = ep.title
        child.url = ep.url
        meta = {
            uuid: ep.uuid,
            podcast: ep.podcast,
            podcastName: ep.podcastName,
            playedUpTo: ep.playedUpTo,
            duration: ep.duration,
            published: ep.published
        }
        child.description = FormatJSON(meta)
    end for
    list = m.upNextList.findNode("list")
    if list <> invalid
        list.content = content
        list.jumpToItem = 0
        list.setFocus(true)
    end if
    if episodes.count() = 0
        m.status.text = "No episodes in Up Next."
    else
        m.status.text = episodes.count().ToStr() + " episodes"
    end if
End Sub

' ---- new releases ---------------------------------------------------------

Sub showNewReleases()
    print "[MainScene] showNewReleases"
    m.mode = "new_releases"
    m.title.text = "PocketStreams — New Releases"
    m.status.text = "Loading..."
    m.stationList.visible = false
    m.upNextList.visible = true
    list = m.upNextList.findNode("list")
    if list <> invalid then list.setFocus(true)
    loadNewReleases()
End Sub

Sub loadNewReleases()
    m.relay = CreateObject("roSGNode", "RelayTask")
    m.relay.observeField("response", "onNewReleasesLoaded")
    m.relay.bodyJson = FormatJSON({
        action: "newReleases",
        token: m.auth.token
    })
    m.relay.control = "RUN"
End Sub

Sub onNewReleasesLoaded()
    print "[MainScene] onNewReleasesLoaded status="; m.relay.status
    if m.relay.status = 401 or m.relay.status = 403
        logout()
        return
    end if
    if m.relay.status <> 200
        m.status.text = "Failed to load New Releases. Check network."
        return
    end if
    data = ParseJSON(m.relay.response)
    if data = invalid or data.episodes = invalid or data.episodes.count() = 0
        m.status.text = "No new episodes in the last 14 days."
        return
    end if
    content = createObject("roSGNode", "ContentNode")
    for each ep in data.episodes
        child = content.createChild("ContentNode")
        child.title = ep.title
        child.url = ep.url
        meta = {
            uuid: ep.uuid,
            podcast: ep.podcast,
            podcastName: ep.podcastName,
            playedUpTo: 0,
            duration: ep.duration,
            published: ep.published
        }
        child.description = FormatJSON(meta)
        artPodcast = ep.podcast
        if ep.artworkUrl <> invalid and ep.artworkUrl <> ""
            child.HDPosterUrl = ep.artworkUrl
        end if
    end for
    list = m.upNextList.findNode("list")
    if list <> invalid
        list.content = content
        list.jumpToItem = 0
        list.setFocus(true)
    end if
    m.status.text = data.episodes.count().ToStr() + " new episodes"
End Sub

Sub onEpisodeSelected()
    index = m.upNextList.itemSelected
    list = m.upNextList.findNode("list")
    if list = invalid then return
    content = list.content
    if content = invalid then return
    item = content.getChild(index)
    if item = invalid then return

    if index = 0 and m.mode = "up_next"
        playEpisode(item)
    else
        meta = ParseJSON(item.description)
        if meta = invalid then return
        m.pendingPlayItem = item
        m.status.text = "Moving to top..."
        m.changeTask = CreateObject("roSGNode", "RelayTask")
        m.changeTask.observeField("response", "onPlayNowDone")
        m.changeTask.bodyJson = FormatJSON({
            action: "upNextChange",
            token: m.auth.token,
            change: "playNow",
            deviceId: m.deviceId,
            uuid: meta.uuid,
            title: item.title,
            url: item.url,
            podcast: meta.podcast
        })
        m.changeTask.control = "RUN"
    end if
End Sub

Sub onPlayNowDone()
    print "[MainScene] playNow done status="; m.changeTask.status
    if m.pendingPlayItem <> invalid
        playEpisode(m.pendingPlayItem)
        m.pendingPlayItem = invalid
    end if
End Sub

Sub playEpisode(item)
    if m.audio = invalid
        m.audio = m.top.createChild("Audio")
        m.audio.observeField("state", "onAudioState")
    end if
    m.audio.control = "stop"

    meta = ParseJSON(item.description)

    audioContent = createObject("roSGNode", "ContentNode")
    audioContent.url = item.url
    audioContent.streamformat = inferStreamformat(item.url, "")

    playStart = 0
    if meta <> invalid and meta.playedUpTo <> invalid and meta.playedUpTo > 0
        playStart = meta.playedUpTo
    end if
    print "[MainScene] playEpisode playStart="; playStart; " duration="; meta.duration
    if playStart > 0
        audioContent.PlayStart = playStart
    end if

    m.audio.content = audioContent
    m.audio.control = "play"

    m.isCurrentlyLive = false
    stopTracklist()
    m.status.text = "Playing: " + item.title
    podcastName = ""
    if meta.podcastName <> invalid then podcastName = meta.podcastName
    artworkUrl = "https://static.pocketcasts.com/discover/images/420/" + meta.podcast + ".jpg"
    m.currentEpisode = {
        uuid: meta.uuid,
        podcast: meta.podcast,
        podcastName: podcastName,
        title: item.title,
        url: item.url,
        duration: meta.duration
    }
    showNowPlaying(item.title, podcastName, artworkUrl, false)

    m.lastSavedPosition = playStart
    if m.saveTimer = invalid
        m.saveTimer = m.top.createChild("Timer")
        m.saveTimer.duration = 30
        m.saveTimer.repeat = true
        m.saveTimer.observeField("fire", "onSaveTimer")
    end if
    m.saveTimer.control = "start"
End Sub

Sub showNowPlaying(title as string, podcastName as string, artworkUrl as string, isLive as boolean)
    m.mode = "now_playing"
    m.nowPlaying.trackTitle  = title
    m.nowPlaying.podcastName = podcastName
    m.nowPlaying.artworkUrl  = artworkUrl
    m.nowPlaying.isLive      = isLive
    m.nowPlaying.playPos     = 0
    m.nowPlaying.duration    = 0
    if m.currentEpisode <> invalid
        m.nowPlaying.duration = m.currentEpisode.duration
    end if
    m.nowPlaying.skipBack  = m.skipBack
    m.nowPlaying.skipFwd   = m.skipFwd
    m.nowPlaying.playState = "playing"
    m.nowPlaying.visible   = true
    m.nowPlaying.setFocus(true)

    if m.posTimer = invalid
        m.posTimer = m.top.createChild("Timer")
        m.posTimer.duration = 1
        m.posTimer.repeat   = true
        m.posTimer.observeField("fire", "onPosTimer")
    end if
    m.posTimer.control = "start"
End Sub

Sub hideNowPlaying()
    m.nowPlaying.visible = false
    if m.posTimer <> invalid then m.posTimer.control = "stop"
    if m.currentEpisode <> invalid
        m.mode = "up_next"
        m.upNextList.visible = true
        list = m.upNextList.findNode("list")
        if list <> invalid then list.setFocus(true)
    else
        if m.mode <> "favorites" and m.mode <> "browse" and m.mode <> "search"
            m.mode = "up_next"
            m.upNextList.visible = true
        end if
        list = m.stationList.findNode("list")
        if list <> invalid and m.stationList.visible then list.setFocus(true)
        ulist = m.upNextList.findNode("list")
        if ulist <> invalid and m.upNextList.visible then ulist.setFocus(true)
    end if
End Sub

Sub onPosTimer()
    if m.audio = invalid then return
    if not m.nowPlaying.visible then return
    curPos = m.audio.position
    if curPos = invalid then return
    m.nowPlaying.playPos = curPos
    if m.currentEpisode = invalid and not m.isCurrentlyLive
        durVal = m.audio.getField("duration")
        if durVal <> invalid and durVal > 0
            m.nowPlaying.duration = CInt(durVal)
        end if
    end if
    audioState = m.audio.state
    if audioState <> invalid
        m.nowPlaying.playState = audioState
    end if
End Sub

Sub onSaveTimer()
    if m.audio = invalid or m.currentEpisode = invalid then return
    curPos = m.audio.position
    if curPos = invalid then return
    if curPos > m.lastSavedPosition + 5
        saveEpisodePosition(curPos, 2)
        m.lastSavedPosition = curPos
    end if
End Sub

Sub saveEpisodePosition(position, status)
    if m.currentEpisode = invalid then return
    m.saveTask = CreateObject("roSGNode", "RelayTask")
    m.saveTask.observeField("response", "onEpisodeSaved")
    m.saveTask.bodyJson = FormatJSON({
        action: "updateEpisode",
        token: m.auth.token,
        uuid: m.currentEpisode.uuid,
        podcast: m.currentEpisode.podcast,
        position: Int(position),
        status: status,
        duration: m.currentEpisode.duration
    })
    m.saveTask.control = "RUN"
End Sub

Sub onEpisodeSaved()
    print "[MainScene] Episode position saved."
End Sub

Sub removeFromUpNext(episode)
    m.changeTask = CreateObject("roSGNode", "RelayTask")
    m.changeTask.observeField("response", "onChangeDone")
    m.changeTask.bodyJson = FormatJSON({
        action: "upNextChange",
        token: m.auth.token,
        change: "remove",
        deviceId: m.deviceId,
        uuid: episode.uuid,
        title: episode.title,
        url: episode.url,
        podcast: episode.podcast
    })
    m.changeTask.control = "RUN"
End Sub

Sub finishAndAdvance(episode)
    m.finishTask = CreateObject("roSGNode", "RelayTask")
    m.finishTask.observeField("response", "onFinishDone")
    m.finishTask.bodyJson = FormatJSON({
        action: "finishEpisode",
        token: m.auth.token,
        uuid: episode.uuid,
        podcast: episode.podcast,
        title: episode.title,
        url: episode.url,
        duration: episode.duration,
        deviceId: m.deviceId
    })
    m.finishTask.control = "RUN"
End Sub

Sub onFinishDone()
    print "[MainScene] finishEpisode done status="; m.finishTask.status
    advanceQueue()
End Sub

Sub onChangeDone()
    print "[MainScene] Up Next change applied."
End Sub

Sub advanceQueue()
    list = m.upNextList.findNode("list")
    if list = invalid then return
    content = list.content
    if content = invalid or content.getChildCount() <= 1 then
        m.status.text = "Queue finished."
        return
    end if
    content.removeChildIndex(0)
    list.content = invalid
    list.content = content
    nextItem = content.getChild(0)
    if nextItem <> invalid
        playEpisode(nextItem)
    end if
End Sub

Function FormatDuration(seconds as integer) as string
    h = seconds \ 3600
    m = (seconds Mod 3600) \ 60
    s = seconds Mod 60
    if h > 0
        return h.ToStr() + ":" + ZeroPad(m) + ":" + ZeroPad(s)
    else
        return m.ToStr() + ":" + ZeroPad(s)
    end if
End Function

Function ZeroPad(n as integer) as string
    if n < 10
        return "0" + n.ToStr()
    else
        return n.ToStr()
    end if
End Function

Sub onAudioState()
    if m.audio = invalid then return
    if m.nowPlaying.visible then m.nowPlaying.playState = m.audio.state

    if m.audio.state = "finished"
        if m.currentEpisode <> invalid
            if m.saveTimer <> invalid then m.saveTimer.control = "stop"
            finishAndAdvance(m.currentEpisode)
        else if m.currentStation <> invalid
            m.status.text = "Stream ended."
        end if
    else if m.audio.state = "paused" or m.audio.state = "stopped"
        if m.currentEpisode <> invalid
            saveEpisodePosition(m.audio.position, 2)
        end if
        if m.saveTimer <> invalid then m.saveTimer.control = "stop"
        stopTracklist()
    else if m.audio.state = "playing"
        if m.currentEpisode <> invalid and m.saveTimer <> invalid
            m.saveTimer.control = "start"
        end if
    else if m.audio.state = "error"
        stopTracklist()
        if m.saveTimer <> invalid then m.saveTimer.control = "stop"
        if m.posTimer  <> invalid then m.posTimer.control  = "stop"
        if m.nowPlaying.visible then hideNowPlaying()
        m.status.text = "Playback error. Check network and try again."
        print "[MainScene] audio error"
    end if
End Sub

' ---- favorites actions -----------------------------------------------------

Sub toggleFavorite()
    list = m.stationList.findNode("list")
    if list = invalid then return
    focusedIndex = m.stationList.itemFocused
    content = list.content
    if content = invalid then return
    item = content.getChild(focusedIndex)
    if item = invalid then return

    stationId = ""
    meta = ParseJSON(item.description)
    if meta <> invalid and meta.stationuuid <> invalid
        stationId = meta.stationuuid
    end if
    if stationId = "" then return

    if m.mode = "favorites"
        removeFavorite(stationId)
    else
        addFavorite(stationId)
    end if
End Sub

Sub addFavorite(stationId as string)
    m.status.text = "Adding favorite..."
    m.http = CreateObject("roSGNode", "HttpJsonTask")
    m.http.observeField("response", "onFavoriteAdded")
    m.http.url = SupabaseUrl() + "/rest/v1/radio_favorites"
    m.http.method = "POST"
    m.http.headers = {
        apikey: SupabaseAnonKey(),
        "x-user-uuid": m.auth.userid,
        "Content-Type": "application/json",
        "Prefer": "return=minimal,resolution=merge-duplicates"
    }
    m.http.body = FormatJSON({ user_uuid: m.auth.userid, station_id: stationId })
    m.http.control = "RUN"
End Sub

Sub onFavoriteAdded()
    if m.http.status >= 200 and m.http.status < 300
        m.status.text = "Favorite added."
    else
        m.status.text = "Failed to add favorite."
    end if
End Sub

Sub removeFavorite(stationId as string)
    m.status.text = "Removing favorite..."
    m.http = CreateObject("roSGNode", "HttpJsonTask")
    m.http.observeField("response", "onFavoriteRemoved")
    m.http.url = SupabaseUrl() + "/rest/v1/radio_favorites?station_id=eq." + stationId + "&user_uuid=eq." + m.auth.userid
    m.http.method = "DELETE"
    m.http.headers = {
        apikey: SupabaseAnonKey(),
        "x-user-uuid": m.auth.userid,
        "Prefer": "return=minimal"
    }
    m.http.body = ""
    m.http.control = "RUN"
End Sub

Sub onFavoriteRemoved()
    if m.http.status >= 200 and m.http.status < 300
        m.status.text = "Favorite removed."
        if m.mode = "favorites"
            loadFavorites()
        end if
    else
        m.status.text = "Failed to remove favorite."
    end if
End Sub

' ---- tracklist -------------------------------------------------------------

Sub startTracklist(stationName as string)
    stopTracklist()
    nameLow = LCase(stationName)
    trackType = ""
    if nameLow.Instr(0, "kcrw") >= 0 then trackType = "kcrw"
    if nameLow.Instr(0, "kexp") >= 0 then trackType = "kexp"
    if trackType = "" then return
    m.tracklistType = trackType
    fetchTracklist()
    m.tracklistTimer = m.top.createChild("Timer")
    m.tracklistTimer.duration = 30
    m.tracklistTimer.repeat   = true
    m.tracklistTimer.observeField("fire", "onTracklistTimer")
    m.tracklistTimer.control = "start"
End Sub

Sub stopTracklist()
    if m.tracklistTimer <> invalid
        m.tracklistTimer.control = "stop"
        m.tracklistTimer = invalid
    end if
    m.tracklistType = ""
End Sub

Sub onTracklistTimer()
    fetchTracklist()
End Sub

Sub fetchTracklist()
    if m.tracklistType = "kcrw"
        m.trackHttp = CreateObject("roSGNode", "HttpJsonTask")
        m.trackHttp.observeField("response", "onTracklistLoaded")
        m.trackHttp.url = "https://tracklist-api.kcrw.com/Music/all/1?page_size=10"
        m.trackHttp.control = "RUN"
    else if m.tracklistType = "kexp"
        m.trackHttp = CreateObject("roSGNode", "HttpJsonTask")
        m.trackHttp.observeField("response", "onTracklistLoaded")
        m.trackHttp.url = "https://api.kexp.org/v2/plays/?limit=10"
        m.trackHttp.control = "RUN"
    end if
End Sub

Sub onTracklistLoaded()
    if m.trackHttp.status <> 200 then return
    data = ParseJSON(m.trackHttp.response)
    if data = invalid then return
    trackText = ""
    if m.tracklistType = "kcrw"
        if type(data) = "roArray" and data.count() > 0
            for each entry in data
                artist = entry.artist
                title  = entry.title
                if artist <> invalid and artist <> "" and artist <> "[BREAK]" and title <> invalid and title <> ""
                    trackText = title + " -- " + artist
                    exit for
                end if
            end for
        end if
    else if m.tracklistType = "kexp"
        results = data.results
        if results <> invalid and results.count() > 0
            for each entry in results
                if entry.play_type = "trackplay" and entry.song <> invalid and entry.song <> ""
                    artist = entry.artist
                    if artist = invalid then artist = ""
                    trackText = entry.song
                    if artist <> "" then trackText = trackText + " -- " + artist
                    exit for
                end if
            end for
        end if
    end if
    if trackText <> "" and m.nowPlaying.visible
        m.nowPlaying.podcastName = trackText
    end if
End Sub

' ---- detail screens --------------------------------------------------------

Sub showEpisodeDetail()
    mode = m.mode
    list = m.upNextList.findNode("list")
    if list = invalid then return
    focusIdx = m.upNextList.itemFocused
    if focusIdx < 0 then focusIdx = 0
    item = list.content.getChild(focusIdx)
    if item = invalid then return
    meta = ParseJSON(item.description)
    if meta = invalid then return

    m.detailStationId = ""
    m.detailPrevMode  = mode
    m.detailScreen.heading    = "EPISODE DETAIL"
    m.detailScreen.titleText  = item.title
    m.detailScreen.subtitle   = meta.podcastName
    m.detailScreen.artworkUrl = "https://static.pocketcasts.com/discover/images/420/" + meta.podcast + ".jpg"
    m.detailScreen.bodyText   = "Loading show notes..."
    m.detailScreen.hintText   = "Back  (Back btn)   |   Right  Detail"
    m.detailScreen.visible    = true
    m.mode = "detail"

    m.showNotesTask = CreateObject("roSGNode", "HttpJsonTask")
    m.showNotesTask.observeField("response", "onShowNotesLoaded")
    m.showNotesTask.url = "https://cache.pocketcasts.com/mobile/show_notes/full/" + meta.podcast
    m.showNotesTask.control = "RUN"
    m.pendingShowNotesUuid = meta.uuid
End Sub

Sub onShowNotesLoaded()
    if m.showNotesTask.status <> 200
        m.detailScreen.bodyText = "Could not load show notes."
        return
    end if
    data = ParseJSON(m.showNotesTask.response)
    if data = invalid then
        m.detailScreen.bodyText = "Could not parse show notes."
        return
    end if
    episodes = data.podcast.episodes
    notes = ""
    for each ep in episodes
        if ep.uuid = m.pendingShowNotesUuid
            if ep.show_notes <> invalid then notes = ep.show_notes
        end if
    end for
    if notes = ""
        m.detailScreen.bodyText = "(No show notes available.)"
        return
    end if
    m.detailScreen.bodyText = StripHtml(notes)
End Sub

Function StripHtml(txt as string) as string
    result = CreateObject("roRegex", "<[^>]*>", "i").ReplaceAll(txt, "")
    result = result.Replace("&amp;", "&")
    result = result.Replace("&lt;", "<")
    result = result.Replace("&gt;", ">")
    result = result.Replace("&quot;", Chr(34))
    result = result.Replace("&#39;", "'")
    result = result.Replace("&nbsp;", " ")
    result = result.Replace("&hellip;", "...")
    result = result.Replace("&#8230;", "...")
    result = result.Replace("&#8216;", "'")
    result = result.Replace("&#8217;", "'")
    result = result.Replace("&#8220;", Chr(34))
    result = result.Replace("&#8221;", Chr(34))
    result = CreateObject("roRegex", "\n\n+", "").ReplaceAll(result, Chr(10))
    return result.Trim()
End Function

Sub showStationDetail()
    list = m.stationList.findNode("list")
    if list = invalid then return
    focusIdx = m.stationList.itemFocused
    if focusIdx < 0 then focusIdx = 0
    item = list.content.getChild(focusIdx)
    if item = invalid then return
    meta = ParseJSON(item.description)
    if meta = invalid then return

    stationId = ""
    if meta.stationuuid <> invalid then stationId = meta.stationuuid

    bodyLines = []
    if meta.display <> invalid and meta.display <> ""
        bodyLines.push("Country:  " + meta.display)
    end if
    if meta.codec <> invalid and meta.codec <> ""
        codecStr = meta.codec
        if meta.bitrate <> invalid and meta.bitrate > 0
            codecStr = codecStr + " / " + meta.bitrate.ToStr() + " kbps"
        end if
        bodyLines.push("Format:   " + codecStr)
    end if

    isFav = (m.mode = "favorites")
    favHint = "  |   Left  Add Favorite"
    if isFav then favHint = "  |   Left  Remove Favorite"

    m.detailStationId = stationId
    m.detailIsFav     = isFav
    m.detailPrevMode  = m.mode
    m.detailScreen.heading    = "STATION DETAIL"
    m.detailScreen.titleText  = item.title
    m.detailScreen.subtitle   = ""
    m.detailScreen.artworkUrl = item.HDPosterUrl
    m.detailScreen.bodyText   = bodyLines.Join(Chr(10))
    m.detailScreen.hintText   = "Back  (Back)" + favHint
    m.detailScreen.visible    = true
    m.mode = "detail"
End Sub

Sub hideDetail()
    m.detailScreen.visible = false
    prevMode = m.detailPrevMode
    if prevMode = "up_next" or prevMode = "new_releases"
        m.mode = prevMode
        list = m.upNextList.findNode("list")
        if list <> invalid then list.setFocus(true)
    else
        m.mode = prevMode
        list = m.stationList.findNode("list")
        if list <> invalid then list.setFocus(true)
    end if
End Sub

' ---- menu ------------------------------------------------------------------

Sub showMenu()
    m.mode = "menu"
    dlg = CreateObject("roSGNode", "Dialog")
    dlg.title = "Menu"
    dlg.buttons = ["Up Next", "New Releases", "Radio Favorites", "Browse Stations", "Search Stations", "Log Out"]
    m.dlg = dlg
    dlg.observeField("buttonSelected", "onMenuBtn")
    dlg.observeField("wasClosed", "onMenuClosed")
    m.top.dialog = dlg
End Sub

Sub onMenuBtn()
    btn = m.dlg.buttonSelected
    closeDialog()
    if btn = 0
        showUpNext()
    else if btn = 1
        showNewReleases()
    else if btn = 2
        showFavorites()
    else if btn = 3
        showBrowse()
    else if btn = 4
        showSearch()
    else if btn = 5
        logout()
    end if
End Sub

Sub onMenuClosed()
    if m.mode = "menu"
        m.mode = "up_next"
        m.stationList.visible = false
        m.upNextList.visible = true
        list = m.upNextList.findNode("list")
        if list <> invalid then list.setFocus(true)
        loadUpNext()
    end if
End Sub

' ---- logout ----------------------------------------------------------------

Sub logout()
    if m.audio <> invalid then m.audio.control = "stop"
    if m.saveTimer <> invalid then m.saveTimer.control = "stop"
    if m.posTimer  <> invalid then m.posTimer.control  = "stop"
    stopTracklist()
    m.nowPlaying.visible    = false
    m.detailScreen.visible  = false
    m.currentEpisode = invalid
    AuthClear()
    m.auth = invalid
    m.top.dialog = invalid
    m.stationList.visible = false
    m.upNextList.visible = false
    list = m.stationList.findNode("list")
    if list <> invalid then list.content = invalid
    ulist = m.upNextList.findNode("list")
    if ulist <> invalid then ulist.content = invalid
    m.title.text = "PocketStreams"
    m.status.text = "Logged out."
    promptEmail()
End Sub

' ---- key events ------------------------------------------------------------

Function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if m.mode = "now_playing"
        if key = "back"
            hideNowPlaying()
            return true
        else if key = "play"
            if m.audio <> invalid
                if m.audio.state = "playing"
                    m.audio.control = "pause"
                else
                    m.audio.control = "resume"
                end if
            end if
            return true
        else if key = "left" or key = "rewind"
            if m.audio <> invalid and not m.isCurrentlyLive
                seekPos = m.audio.getField("position") - m.skipBack
                if seekPos < 0 then seekPos = 0
                m.audio.seek = seekPos
            end if
            return true
        else if key = "right" or key = "fastforward"
            if m.audio <> invalid and not m.isCurrentlyLive
                m.audio.seek = m.audio.getField("position") + m.skipFwd
            end if
            return true
        end if
        return false
    end if
    if m.mode = "detail"
        if key = "back"
            hideDetail()
            return true
        else if key = "left"
            if m.detailStationId <> "" and m.detailStationId <> invalid
                if m.detailIsFav
                    removeFavorite(m.detailStationId)
                else
                    addFavorite(m.detailStationId)
                end if
                hideDetail()
            end if
            return true
        end if
        return false
    end if
    if m.mode = "up_next" or m.mode = "new_releases"
        if key = "back"
            showMenu()
            return true
        else if key = "right"
            showEpisodeDetail()
            return true
        else if key = "play"
            if m.audio <> invalid
                if m.audio.state = "playing"
                    m.audio.control = "pause"
                else
                    m.audio.control = "resume"
                end if
            end if
            return true
        end if
    else if m.mode = "favorites" or m.mode = "browse" or m.mode = "search"
        if key = "back"
            if m.mode = "favorites"
                showMenu()
                return true
            else
                showFavorites()
                return true
            end if
        else if key = "right"
            showStationDetail()
            return true
        else if key = "play"
            if m.audio <> invalid
                if m.audio.state = "playing"
                    m.audio.control = "pause"
                else
                    m.audio.control = "resume"
                end if
            end if
            return true
        end if
    end if
    return false
End Function
