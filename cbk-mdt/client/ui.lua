CBK_MDT_Client = CBK_MDT_Client or {}

CBK_MDT_Client.state = {
    isOpen = false,
    pending = {}
}

function CBK_MDT_Client.SetOpen(state)
    CBK_MDT_Client.state.isOpen = state == true
    SetNuiFocus(CBK_MDT_Client.state.isOpen, CBK_MDT_Client.state.isOpen)
    SetNuiFocusKeepInput(false)

    SendNUIMessage({
        type = 'mdt:setOpen',
        payload = { isOpen = CBK_MDT_Client.state.isOpen }
    })
end

function CBK_MDT_Client.Notify(msg, notifyType)
    local text = tostring(msg or 'Unknown message')
    TriggerEvent('chat:addMessage', {
        color = notifyType == 'error' and { 255, 80, 80 } or { 80, 180, 255 },
        multiline = true,
        args = { '[MDT]', text }
    })
end