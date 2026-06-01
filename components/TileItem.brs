Sub init()
    m.focusBorder = m.top.findNode("focusBorder")
    m.bg          = m.top.findNode("bg")
    m.art         = m.top.findNode("art")
    m.nowBg       = m.top.findNode("nowBg")
    m.nowLabel    = m.top.findNode("nowLabel")
    m.titleLabel  = m.top.findNode("titleLabel")
    m.metaLabel   = m.top.findNode("metaLabel")
End Sub

Sub onFocus()
    focused = m.top.focusPercent > 0.5
    if focused
        m.bg.color            = "0x1E333DFF"
        m.focusBorder.visible = true
    else
        m.bg.color            = "0x1A1B1DFF"
        m.focusBorder.visible = false
    end if
End Sub

Sub onContentSet()
    item = m.top.itemContent
    if item = invalid then return
    m.titleLabel.text = item.title
    if item.HDPosterUrl <> invalid and item.HDPosterUrl <> ""
        m.art.uri = item.HDPosterUrl
    else
        m.art.uri = ""
    end if
    metaText = ""
    desc = item.description
    if desc <> invalid and desc <> ""
        meta = ParseJSON(desc)
        if meta <> invalid
            if meta.isStation = true
                if meta.codec <> invalid and meta.codec <> ""
                    metaText = meta.codec
                    if meta.bitrate <> invalid and meta.bitrate > 0
                        metaText = metaText + " " + CStr(meta.bitrate) + "k"
                    end if
                else if meta.display <> invalid and meta.display <> ""
                    metaText = meta.display
                end if
            else
                dur = CInt(meta.duration)
                played = CInt(meta.playedUpTo)
                if dur > 0
                    if played > 0
                        left = dur - played
                        metaText = TileFmt(left) + " left"
                    else
                        metaText = TileFmt(dur)
                    end if
                end if
            end if
        end if
    end if
    m.metaLabel.text = metaText
End Sub

Sub onNowPlayingChanged()
    playing = m.top.isNowPlaying
    m.nowBg.visible    = playing
    m.nowLabel.visible = playing
End Sub

Function TileFmt(secs as integer) as string
    h    = secs \ 3600
    mins = (secs Mod 3600) \ 60
    if h > 0
        return h.ToStr() + "h " + mins.ToStr() + "m"
    end if
    return mins.ToStr() + "m"
End Function

Function CStr(val) as string
    return val.ToStr()
End Function
