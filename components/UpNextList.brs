Sub init()
    m.list = m.top.findNode("list")
    m.list.observeField("itemSelected", "onItemSelected")
    m.list.observeField("itemFocused", "onItemFocused")
End Sub

Sub onItemSelected()
    m.top.itemSelected = m.list.itemSelected
End Sub

Sub onItemFocused()
    m.top.itemFocused = m.list.itemFocused
End Sub
