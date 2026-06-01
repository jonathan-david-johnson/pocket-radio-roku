Sub init()
    m.headingLabel  = m.top.findNode("heading")
    m.titleLabel    = m.top.findNode("titleLabel")
    m.subtitleLabel = m.top.findNode("subtitleLabel")
    m.bodyLabel     = m.top.findNode("bodyLabel")
    m.hintLabel     = m.top.findNode("hintLabel")
    m.artwork       = m.top.findNode("artwork")
End Sub

Sub onArtworkChanged()
    url = m.top.artworkUrl
    if url <> invalid and url <> ""
        m.artwork.uri = url
    else
        m.artwork.uri = ""
    end if
End Sub

Sub onDataChanged()
    if m.headingLabel  <> invalid then m.headingLabel.text  = m.top.heading
    if m.titleLabel    <> invalid then m.titleLabel.text    = m.top.titleText
    if m.subtitleLabel <> invalid then m.subtitleLabel.text = m.top.subtitle
    if m.bodyLabel     <> invalid then m.bodyLabel.text     = m.top.bodyText
    if m.hintLabel     <> invalid then m.hintLabel.text     = m.top.hintText
End Sub
