node.setcpufreq(node.CPU160MHZ)

dofile('httpServer.lua')

wifi.setmode(wifi.STATION)
wifi.sta.sethostname('Timor-WIFI-Boot')

local WIFI_conn_history = false
local SSID = nil
local PWD = nil
local WIFI_connected = false
local AP_enabled = false

local i2cPort = 0
local i2cSDA = 5
local i2cSCL = 6
local i2cSpeed = i2c.FASTPLUS

local OLEDAddress = 0x3c

local saveWIFI = function (ssid, pwd)
	local cfd = file.open('credential', 'w')
	cfd:writeline('SSID='..ssid)
	cfd:writeline('PWD='..pwd)
	cfd:flush()
	cfd:close()
end

local getWIFI = function ()
	if (not file.exists('credential')) then
		return nil
	end
	local cfd = file.open('credential', 'r')
	local ssid = cfd:readline()
	local pwd = cfd:readline()
	cfd:close()
	local credential = {}
	ssid = string.sub(ssid, 6, -2)
	pwd = string.sub(pwd, 5, -2)
	credential['ssid'] = ssid
	credential['pwd'] = pwd
	return credential
end

local History = getWIFI()
if (History) then
	WIFI_conn_history = true
	SSID = History['ssid']
	PWD = History['pwd']
end

i2c.setup(i2cPort, i2cSDA, i2cSCL, i2cSpeed)

local oled = u8g2.ssd1306_i2c_128x32_univision(i2cPort, OLEDAddress)
oled:setFontRefHeightExtendedText()
oled:setFontPosTop()

local defaultFont = function ()
	oled:setFont(u8g2.font_profont11_tf)
end

local font_helvB14_tr = function ()
	oled:setFont(u8g2.font_helvB14_tr)
end

local onWifiDisconnect = function ()
	if (WIFI_connected == false and AP_enabled == true) then
		return
	end
	WIFI_connected = false
	print('wifi disconnected.')
	if (AP_enabled == false) then
		AP_enabled = true
		collectgarbage()
		wifi.setmode(wifi.STATIONAP)
	  wifi.ap.config({ssid="Timor-WIFI-Boot", auth=wifi.OPEN})
	  httpServer:listen(80)
	  print('AP enabled.')
	end
end

local onWifiConnect = function (ip)
	if (WIFI_connected == true) then
		return
	end
	WIFI_connected = true
	print('wifi connected. '..ip)
	if (AP_enabled == true) then
		AP_enabled = false
		collectgarbage()
		wifi.setmode(wifi.STATION)
		httpServer:close()
		print('AP closed.')
	end
	sntp.sync()
end

local onWIFIHistory = function (ssid, pwd)
	if (WIFI_conn_history == false) then
		WIFI_conn_history = true
		SSID = ssid
		PWD = pwd
		wifi.sta.config({ssid=ssid, pwd=pwd, save=true})
	end
end

local networkMonitor = function ()
	local ip = wifi.sta.getip()
	if (ip == nil) then
		local credential = getWIFI()
		if (credential) then
			onWIFIHistory(credential['ssid'], credential['pwd'])
			return
		end
    onWifiDisconnect()
  else
  	onWifiConnect(ip)
  end
end

local monitor_timer = tmr.create()
monitor_timer:alarm(5000, tmr.ALARM_AUTO, networkMonitor)

local renderOnHistory = function ()
	oled:drawStr(0, 0, 'Connecting: '..SSID)
end

local renderOnStartup = function ()
	oled:drawStr(0, 0, 'Startup...')
end

local renderOnSetup = function ()
	oled:drawStr(0, 0, 'Waiting for User...')
end

local renderOnConnected = function ()
	font_helvB14_tr()
	local rtm = rtctime.epoch2cal(rtctime.get())
	oled:drawStr(28, 0, string.format("%02d:%02d:%02d", rtm['hour']+8, rtm['min'], rtm['sec']))
end

local renderDisplay = function ()
	oled:clearBuffer()
	defaultFont()
	if (WIFI_connected == false) then
		if (WIFI_conn_history == true) then
			renderOnHistory()
		elseif (AP_enabled == false) then
			renderOnStartup()
		else
			renderOnSetup()
		end
	elseif (WIFI_connected == true) then
		renderOnConnected()
	end
	oled:sendBuffer()
end

local oled_timer = tmr.create()
oled_timer:alarm(1000, tmr.ALARM_AUTO, renderDisplay)

httpServer:use('/connect', function(req, res)
  print('start connect wifi: '..req.query.ssid..' password: '..req.query.password)
  res:send('success')
  saveWIFI(req.query.ssid, req.query.password)
  wifi.sta.config({ssid=req.query.ssid, pwd=req.query.password, save=true})
end)
