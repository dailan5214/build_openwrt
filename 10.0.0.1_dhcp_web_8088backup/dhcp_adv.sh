#!/bin/sh

# CGI 输出头
printf 'Content-Type: text/html; charset=UTF-8\r\n\r\n'

urldecode() {
  local data
  data=$(echo "$1" | sed 's/+/ /g;s/%/\\x/g')
  printf '%b' "$data"
}

html_escape() {
  echo "$1" | sed \
    -e 's/&/\&amp;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g' \
    -e 's/"/\&quot;/g' \
    -e "s/'/\&#39;/g"
}

normalize_mac() {
  echo "$1" | tr 'A-Z' 'a-z'
}

valid_mac() {
  echo "$1" | grep -Eq '^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}$'
}

valid_ipv4() {
  echo "$1" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'
}

find_host_sec_by_mac() {
  local target sec m
  target=$(normalize_mac "$1")
  for sec in $(uci -q show dhcp | sed -n "s/^dhcp\.\([^.=]*\)=host$/\1/p"); do
    m=$(uci -q get dhcp."$sec".mac)
    m=$(normalize_mac "$m")
    [ "$m" = "$target" ] && {
      echo "$sec"
      return 0
    }
  done
  return 1
}

find_tag_sec_by_tagname() {
  local target sec t
  target="$1"
  [ -z "$target" ] && return 1
  for sec in $(uci -q show dhcp | sed -n "s/^dhcp\.\([^.=]*\)=tag$/\1/p"); do
    t=$(uci -q get dhcp."$sec".tag)
    [ "$t" = "$target" ] && {
      echo "$sec"
      return 0
    }
  done
  return 1
}

is_tag_section() {
  local sec st
  sec="$1"
  [ -z "$sec" ] && return 1
  st=$(uci -q show dhcp."$sec" 2>/dev/null | sed -n "1s/^dhcp\\.$sec=\\(.*\\)$/\\1/p")
  [ "$st" = "tag" ]
}

resolve_tag_sec() {
  local key sec
  key="$1"
  [ -z "$key" ] && return 1
  if is_tag_section "$key"; then
    echo "$key"
    return 0
  fi
  sec=$(find_tag_sec_by_tagname "$key") || return 1
  echo "$sec"
}

get_tag_label_from_host_tag() {
  local host_tag sec label
  host_tag="$1"
  [ -z "$host_tag" ] && {
    echo ""
    return 0
  }
  sec=$(resolve_tag_sec "$host_tag") || {
    echo "$host_tag"
    return 0
  }
  label=$(uci -q get dhcp."$sec".tag)
  [ -n "$label" ] && echo "$label" || echo "$host_tag"
}

delete_adv_tag_by_name() {
  local target sec tname
  target="$1"
  [ -z "$target" ] && return 0
  if is_tag_section "$target"; then
    tname=$(uci -q get dhcp."$target".tag)
    case "$tname" in
      adv_*) uci -q delete dhcp."$target" ;;
    esac
    return 0
  fi
  case "$target" in
    adv_*) ;;
    *) return 0 ;;
  esac
  sec=$(find_tag_sec_by_tagname "$target")
  [ -n "$sec" ] && uci -q delete dhcp."$sec"
}

get_tag_option_value() {
  local tag_name code tsec
  tag_name="$1"
  code="$2"
  tsec=$(resolve_tag_sec "$tag_name") || {
    echo ""
    return 0
  }
  get_section_option_value "$tsec" "$code"
}

get_section_option_value() {
  local sec code opt value options
  sec="$1"
  code="$2"
  value=""
  [ -z "$sec" ] && {
    echo ""
    return 0
  }
  options=$(uci -q get dhcp."$sec".dhcp_option 2>/dev/null)
  for opt in $options; do
    case "$opt" in
      "$code",*)
        value=${opt#*,}
        ;;
    esac
  done
  echo "$value"
}

build_static_mac_set() {
  local sec m
  STATIC_MAC_SET="|"
  for sec in $(uci -q show dhcp | sed -n "s/^dhcp\.\([^.=]*\)=host$/\1/p"); do
    m=$(uci -q get dhcp."$sec".mac)
    m=$(normalize_mac "$m")
    [ -z "$m" ] && continue
    STATIC_MAC_SET="${STATIC_MAC_SET}${m}|"
  done
}

is_static_mac() {
  local m
  m=$(normalize_mac "$1")
  case "$STATIC_MAC_SET" in
    *"|$m|"*) return 0 ;;
    *) return 1 ;;
  esac
}

format_lease_expire() {
  local exp now left
  exp="$1"
  [ -z "$exp" ] && {
    echo "-"
    return 0
  }
  [ "$exp" = "0" ] && {
    echo "永久"
    return 0
  }
  case "$exp" in
    *[!0-9]*)
      echo "$exp"
      return 0
      ;;
  esac
  now=$(date +%s)
  left=$((exp - now))
  [ "$left" -le 0 ] && {
    echo "即将过期"
    return 0
  }
  if [ "$left" -ge 86400 ]; then
    echo "$((left / 86400))天"
  elif [ "$left" -ge 3600 ]; then
    echo "$((left / 3600))小时"
  elif [ "$left" -ge 60 ]; then
    echo "$((left / 60))分钟"
  else
    echo "${left}秒"
  fi
}

read_params() {
  local data pair key val old_ifs
  data="$1"
  old_ifs="$IFS"
  IFS='&'
  for pair in $data; do
    key=${pair%%=*}
    val=${pair#*=}
    [ "$pair" = "$key" ] && val=""
    key=$(urldecode "$key")
    val=$(urldecode "$val")
    case "$key" in
      action) action="$val" ;;
      name) name="$val" ;;
      mac) mac="$val" ;;
      ip) ip="$val" ;;
      gateway) gateway="$val" ;;
      dns) dns="$val" ;;
      tag) tag="$val" ;;
      default_gateway) default_gateway="$val" ;;
      default_dns) default_dns="$val" ;;
      template_tag) template_tag="$val" ;;
      template_gateway) template_gateway="$val" ;;
      template_dns) template_dns="$val" ;;
      template_sec) template_sec="$val" ;;
      enable) enable="$val" ;;
      editmac) editmac="$val" ;;
    esac
  done
  IFS="$old_ifs"
}

restart_dnsmasq() {
  /etc/init.d/dnsmasq restart >/dev/null 2>&1
}

apply_save() {
  local mac_id hostsec tagsec tagname oldsec oldtag dns_norm custom_tag safe_tag tsec idx host_tag_key
  mac=$(normalize_mac "$mac")
  custom_tag=$(echo "$tag" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  [ -z "$name" ] && {
    err='设备名不能为空'
    return 1
  }
  valid_mac "$mac" || {
    err='MAC 格式不正确（示例：AA:BB:CC:DD:EE:FF）'
    return 1
  }
  valid_ipv4 "$ip" || {
    err='IP 格式不正确（示例：10.0.0.120）'
    return 1
  }
  [ -n "$gateway" ] && ! valid_ipv4 "$gateway" && {
    err='网关格式不正确'
    return 1
  }

  dns_norm=$(echo "$dns" | tr ' ' ',' | sed 's/,,*/,/g;s/^,//;s/,$//')
  dns="$dns_norm"

  mac_id=$(echo "$mac" | tr ':' '_' | tr -cd '0-9a-z_')
  hostsec="advh_$mac_id"
  tagsec="advt_$mac_id"
  tagname="adv_$mac_id"

  oldsec=$(find_host_sec_by_mac "$mac")
  oldtag=''
  [ -n "$oldsec" ] && oldtag=$(uci -q get dhcp."$oldsec".tag)
  if [ -n "$oldsec" ] && [ "$oldsec" != "$hostsec" ]; then
    uci -q delete dhcp."$oldsec"
    delete_adv_tag_by_name "$oldtag"
  fi

  uci set dhcp."$hostsec"='host'
  uci set dhcp."$hostsec".name="$name"
  uci set dhcp."$hostsec".mac="$mac"
  uci set dhcp."$hostsec".ip="$ip"

  if [ -n "$custom_tag" ]; then
    tsec=$(resolve_tag_sec "$custom_tag")
    if [ -z "$tsec" ]; then
      if [ -z "$gateway" ] && [ -z "$dns" ]; then
        err='标签不存在，请从模板选择，或同时填写网关/DNS创建新标签'
        return 1
      fi
      safe_tag=$(echo "$custom_tag" | tr 'A-Z' 'a-z' | tr -cs '0-9a-z_' '_')
      [ -z "$safe_tag" ] && safe_tag='custom'
      tsec="tag_${safe_tag}"
      idx=0
      while uci -q show dhcp."$tsec" >/dev/null 2>&1; do
        idx=$((idx + 1))
        tsec="tag_${safe_tag}_$idx"
      done
      uci set dhcp."$tsec"='tag'
      uci set dhcp."$tsec".tag="$custom_tag"
    fi

    host_tag_key="$tsec"
    uci set dhcp."$hostsec".tag="$host_tag_key"
    uci -q delete dhcp."$hostsec".adv_gateway
    uci -q delete dhcp."$hostsec".adv_dns
    delete_adv_tag_by_name "$oldtag"

    if [ -n "$gateway" ] || [ -n "$dns" ]; then
      uci -q delete dhcp."$tsec".dhcp_option
      [ -n "$gateway" ] && uci add_list dhcp."$tsec".dhcp_option="3,$gateway"
      [ -n "$dns" ] && uci add_list dhcp."$tsec".dhcp_option="6,$dns"
    fi
    uci -q delete dhcp."$tagsec"
  elif [ -n "$gateway" ] || [ -n "$dns" ]; then
    uci set dhcp."$hostsec".tag="$tagsec"
    uci set dhcp."$hostsec".adv_gateway="$gateway"
    uci set dhcp."$hostsec".adv_dns="$dns"
    uci set dhcp."$tagsec"='tag'
    uci set dhcp."$tagsec".tag="$tagname"
    uci -q delete dhcp."$tagsec".dhcp_option
    [ -n "$gateway" ] && uci add_list dhcp."$tagsec".dhcp_option="3,$gateway"
    [ -n "$dns" ] && uci add_list dhcp."$tagsec".dhcp_option="6,$dns"
  else
    uci -q delete dhcp."$hostsec".tag
    uci -q delete dhcp."$hostsec".adv_gateway
    uci -q delete dhcp."$hostsec".adv_dns
    uci -q delete dhcp."$tagsec"
    delete_adv_tag_by_name "$oldtag"
  fi

  uci commit dhcp
  restart_dnsmasq
  msg='保存成功'
  return 0
}

apply_delete() {
  local mac_norm sec tag
  mac_norm=$(normalize_mac "$mac")
  valid_mac "$mac_norm" || {
    err='删除失败：MAC 格式不正确'
    return 1
  }
  sec=$(find_host_sec_by_mac "$mac_norm") || {
    err='删除失败：未找到该设备'
    return 1
  }
  tag=$(uci -q get dhcp."$sec".tag)
  uci -q delete dhcp."$sec"
  delete_adv_tag_by_name "$tag"
  uci commit dhcp
  restart_dnsmasq
  msg='删除成功'
  return 0
}

apply_toggle() {
  case "$enable" in
    1)
      uci set dhcp.lan.ignore='0'
      uci commit dhcp
      restart_dnsmasq
      msg='已开启 LAN DHCP'
      ;;
    0)
      uci set dhcp.lan.ignore='1'
      uci commit dhcp
      restart_dnsmasq
      msg='已关闭 LAN DHCP'
      ;;
    *)
      err='切换失败：参数错误'
      return 1
      ;;
  esac
}

apply_save_default() {
  local dns_norm one_dns
  [ -n "$default_gateway" ] && ! valid_ipv4 "$default_gateway" && {
    err='默认网关格式不正确'
    return 1
  }

  dns_norm=$(echo "$default_dns" | tr ' ' ',' | sed 's/,,*/,/g;s/^,//;s/,$//')
  default_dns="$dns_norm"
  if [ -n "$default_dns" ]; then
    for one_dns in $(echo "$default_dns" | tr ',' ' '); do
      valid_ipv4 "$one_dns" || {
        err='默认 DNS 格式不正确'
        return 1
      }
    done
  fi

  uci -q delete dhcp.lan.dhcp_option
  [ -n "$default_gateway" ] && uci add_list dhcp.lan.dhcp_option="3,$default_gateway"
  [ -n "$default_dns" ] && uci add_list dhcp.lan.dhcp_option="6,$default_dns"
  uci commit dhcp
  restart_dnsmasq
  msg='默认 DHCP 规则保存成功'
  return 0
}

apply_save_template() {
  local tname tgw tdns one_dns tsec safe idx
  tname=$(echo "$template_tag" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  tgw=$(echo "$template_gateway" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  tdns=$(echo "$template_dns" | tr ' ' ',' | sed 's/,,*/,/g;s/^,//;s/,$//')

  [ -z "$tname" ] && {
    err='标签名不能为空'
    return 1
  }
  case "$tname" in
    adv_*)
      err='标签名不能以 adv_ 开头'
      return 1
      ;;
  esac

  [ -n "$tgw" ] && ! valid_ipv4 "$tgw" && {
    err='标签网关格式不正确'
    return 1
  }
  if [ -n "$tdns" ]; then
    for one_dns in $(echo "$tdns" | tr ',' ' '); do
      valid_ipv4 "$one_dns" || {
        err='标签 DNS 格式不正确'
        return 1
      }
    done
  fi

  tsec=$(resolve_tag_sec "$tname")
  if [ -z "$tsec" ]; then
    safe=$(echo "$tname" | tr 'A-Z' 'a-z' | tr -cs '0-9a-z_' '_')
    [ -z "$safe" ] && safe='custom'
    tsec="tag_${safe}"
    idx=0
    while uci -q show dhcp."$tsec" >/dev/null 2>&1; do
      idx=$((idx + 1))
      tsec="tag_${safe}_$idx"
    done
    uci set dhcp."$tsec"='tag'
  fi

  uci set dhcp."$tsec".tag="$tname"
  uci -q delete dhcp."$tsec".dhcp_option
  [ -n "$tgw" ] && uci add_list dhcp."$tsec".dhcp_option="3,$tgw"
  [ -n "$tdns" ] && uci add_list dhcp."$tsec".dhcp_option="6,$tdns"

  uci commit dhcp
  restart_dnsmasq
  msg='标签模板保存成功'
  return 0
}

apply_delete_template() {
  local sec tlabel in_use host_sec htag
  sec="$template_sec"
  is_tag_section "$sec" || {
    err='删除失败：标签模板不存在'
    return 1
  }
  tlabel=$(uci -q get dhcp."$sec".tag)
  case "$tlabel" in
    adv_*)
      err='删除失败：系统自动标签不可删除'
      return 1
      ;;
  esac
  in_use=0
  for host_sec in $(uci -q show dhcp | sed -n "s/^dhcp\.\([^.=]*\)=host$/\1/p"); do
    htag=$(uci -q get dhcp."$host_sec".tag)
    [ "$htag" = "$sec" ] && in_use=1
    [ "$htag" = "$tlabel" ] && in_use=1
  done
  [ "$in_use" -eq 1 ] && {
    err='删除失败：还有静态租约正在使用该标签'
    return 1
  }
  uci -q delete dhcp."$sec"
  uci commit dhcp
  restart_dnsmasq
  msg='标签模板删除成功'
  return 0
}

action=''
name=''
mac=''
ip=''
gateway=''
dns=''
tag=''
default_gateway=''
default_dns=''
template_tag=''
template_gateway=''
template_dns=''
template_sec=''
enable=''
editmac=''
msg=''
err=''

if [ "$REQUEST_METHOD" = 'POST' ]; then
  read -r -n "${CONTENT_LENGTH:-0}" body
  read_params "$body"
else
  read_params "$QUERY_STRING"
fi

case "$action" in
  save) apply_save ;;
  delete) apply_delete ;;
  toggle_dhcp) apply_toggle ;;
  save_default) apply_save_default ;;
  save_template) apply_save_template ;;
  delete_template) apply_delete_template ;;
esac

form_name="$name"
form_mac="$mac"
form_ip="$ip"
form_gateway="$gateway"
form_dns="$dns"
form_tag="$tag"

if [ -n "$editmac" ]; then
  sec=$(find_host_sec_by_mac "$editmac")
  if [ -n "$sec" ]; then
    form_name=$(uci -q get dhcp."$sec".name)
    form_mac=$(uci -q get dhcp."$sec".mac)
    form_ip=$(uci -q get dhcp."$sec".ip)
    form_gateway=$(uci -q get dhcp."$sec".adv_gateway)
    form_dns=$(uci -q get dhcp."$sec".adv_dns)
    host_tag=$(uci -q get dhcp."$sec".tag)
    form_tag=$(get_tag_label_from_host_tag "$host_tag")
    [ -z "$form_gateway" ] && [ -n "$host_tag" ] && form_gateway=$(get_tag_option_value "$host_tag" 3)
    [ -z "$form_dns" ] && [ -n "$host_tag" ] && form_dns=$(get_tag_option_value "$host_tag" 6)
    case "$form_tag" in
      adv_*) form_tag="" ;;
    esac
  fi
fi

lan_ignore=$(uci -q get dhcp.lan.ignore)
if [ "$lan_ignore" = '1' ]; then
  dhcp_state='关闭'
  toggle_to='1'
  toggle_label='开启 LAN DHCP'
else
  dhcp_state='开启'
  toggle_to='0'
  toggle_label='关闭 LAN DHCP'
fi

default_gateway_form=$(get_section_option_value "lan" 3)
default_dns_form=$(get_section_option_value "lan" 6)
[ -n "$default_gateway" ] && default_gateway_form="$default_gateway"
[ -n "$default_dns" ] && default_dns_form="$default_dns"

cat <<'HTML_TOP'
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width,initial-scale=1" />
<title>DHCP 高级管理</title>
<style>
body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"PingFang SC","Hiragino Sans GB","Microsoft YaHei",sans-serif;background:#f5f7fb;color:#1f2937;margin:0}
.wrap{max-width:980px;margin:20px auto;padding:0 12px}
.card{background:#fff;border:1px solid #e5e7eb;border-radius:10px;padding:14px;margin-bottom:12px}
h1{font-size:20px;margin:0 0 10px}
.muted{color:#6b7280;font-size:13px}
.ok{background:#ecfdf5;border:1px solid #10b981;color:#065f46;padding:8px;border-radius:8px;margin-bottom:10px}
.err{background:#fef2f2;border:1px solid #ef4444;color:#991b1b;padding:8px;border-radius:8px;margin-bottom:10px}
label{display:block;font-size:13px;color:#374151;margin:8px 0 4px}
input{width:100%;box-sizing:border-box;padding:8px;border:1px solid #d1d5db;border-radius:8px}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:10px}
@media(max-width:720px){.grid{grid-template-columns:1fr}}
button{border:0;background:#2563eb;color:#fff;padding:8px 12px;border-radius:8px;cursor:pointer}
button.gray{background:#6b7280}
button.red{background:#dc2626}
table{width:100%;border-collapse:collapse;font-size:13px}
th,td{border-bottom:1px solid #e5e7eb;padding:8px;text-align:left;vertical-align:top}
.actions form{display:inline-block;margin-right:6px}
a.link{color:#2563eb;text-decoration:none}
</style>
</head>
<body>
<div class="wrap">
  <div class="card">
    <h1>DHCP 静态分配（高级）</h1>
    <div class="muted">入口: http://10.0.0.1:8088/  |  支持每设备网关(DHCP Option 3)和DNS(Option 6)</div>
  </div>
HTML_TOP

[ -n "$msg" ] && printf '<div class="wrap"><div class="ok">%s</div></div>\n' "$(html_escape "$msg")"
[ -n "$err" ] && printf '<div class="wrap"><div class="err">%s</div></div>\n' "$(html_escape "$err")"

cat <<HTML_MID
<div class="wrap">
  <div class="card">
    <form method="post">
      <input type="hidden" name="action" value="toggle_dhcp" />
      <input type="hidden" name="enable" value="$toggle_to" />
      <div class="muted">LAN DHCP 当前状态：<b>$dhcp_state</b></div>
      <div style="margin-top:8px"><button type="submit" class="gray">$toggle_label</button></div>
    </form>
  </div>

  <div class="card">
    <h3 style="margin:0 0 10px;">默认 DHCP 规则（LAN）</h3>
    <form method="post">
      <input type="hidden" name="action" value="save_default" />
      <div class="grid">
        <div>
          <label>默认网关（Option 3）</label>
          <input name="default_gateway" value="$(html_escape "$default_gateway_form")" placeholder="例如 10.0.0.1" />
        </div>
        <div>
          <label>默认 DNS（Option 6，多个逗号分隔）</label>
          <input name="default_dns" value="$(html_escape "$default_dns_form")" placeholder="例如 222.246.129.80,59.51.78.210" />
        </div>
      </div>
      <div style="margin-top:10px"><button class="gray" type="submit">保存默认规则</button></div>
    </form>
  </div>

  <div class="card">
    <form method="post">
      <input type="hidden" name="action" value="save" />
      <div class="grid">
        <div>
          <label>设备名</label>
          <input name="name" value="$(html_escape "$form_name")" placeholder="例如 NAS-01" required />
        </div>
        <div>
          <label>MAC 地址</label>
          <input name="mac" value="$(html_escape "$form_mac")" placeholder="AA:BB:CC:DD:EE:FF" required />
        </div>
        <div>
          <label>静态 IP</label>
          <input name="ip" value="$(html_escape "$form_ip")" placeholder="10.0.0.120" required />
        </div>
        <div>
          <label>网关（可选）</label>
          <input name="gateway" value="$(html_escape "$form_gateway")" placeholder="10.0.0.1" />
        </div>
        <div>
          <label>标签（可选）</label>
          <input name="tag" value="$(html_escape "$form_tag")" placeholder="例如 istoreos 或 8" />
        </div>
      </div>
      <label>DNS（可选，多个用逗号分隔）</label>
      <input name="dns" value="$(html_escape "$form_dns")" placeholder="223.5.5.5,119.29.29.29" />
      <div class="muted" style="margin-top:8px;">说明：填写“标签”后，设备将按标签下发网关/DNS；不填标签则按本设备单独配置。</div>
      <div style="margin-top:10px"><button type="submit">保存 / 更新</button></div>
    </form>
  </div>

  <div class="card">
    <h3 style="margin:0 0 10px;">静态租约（保留地址）</h3>
    <table>
      <thead>
        <tr><th>设备名</th><th>MAC</th><th>IP</th><th>标签</th><th>网关</th><th>DNS</th><th>操作</th></tr>
      </thead>
      <tbody>
HTML_MID

build_static_mac_set
static_found=0
for sec in $(uci -q show dhcp | sed -n "s/^dhcp\.\([^.=]*\)=host$/\1/p"); do
  hname=$(uci -q get dhcp."$sec".name)
  hmac=$(uci -q get dhcp."$sec".mac)
  hip=$(uci -q get dhcp."$sec".ip)
  hgw=$(uci -q get dhcp."$sec".adv_gateway)
  hdns=$(uci -q get dhcp."$sec".adv_dns)
  htag=$(uci -q get dhcp."$sec".tag)

  [ -z "$hgw" ] && [ -n "$htag" ] && hgw=$(get_tag_option_value "$htag" 3)
  [ -z "$hdns" ] && [ -n "$htag" ] && hdns=$(get_tag_option_value "$htag" 6)

  [ -z "$hmac" ] && continue
  static_found=1

  printf '<tr>'
  printf '<td>%s</td>' "$(html_escape "$hname")"
  printf '<td>%s</td>' "$(html_escape "$hmac")"
  printf '<td>%s</td>' "$(html_escape "$hip")"
  if [ -z "$htag" ]; then
    htag_show='-'
  else
    htag_show=$(get_tag_label_from_host_tag "$htag")
    case "$htag_show" in
      adv_*) htag_show='(自动)' ;;
    esac
  fi
  printf '<td>%s</td>' "$(html_escape "$htag_show")"
  printf '<td>%s</td>' "$(html_escape "$hgw")"
  printf '<td>%s</td>' "$(html_escape "$hdns")"
  printf '<td class="actions">'
  printf '<a class="link" href="/cgi-bin/dhcp_adv.sh?editmac=%s">编辑</a> ' "$(html_escape "$hmac")"
  printf '<form method="post"><input type="hidden" name="action" value="delete" /><input type="hidden" name="mac" value="%s" /><button class="red" type="submit">删除</button></form>' "$(html_escape "$hmac")"
  printf '</td>'
  printf '</tr>\n'
done

[ "$static_found" -eq 0 ] && echo '<tr><td colspan="7" class="muted">暂无静态分配记录</td></tr>'

cat <<'HTML_STATIC_END'
      </tbody>
    </table>
  </div>
HTML_STATIC_END

cat <<'HTML_TAG_END'
  <div class="card">
    <h3 style="margin:0 0 10px;">标签模板（Tag）</h3>
    <div class="muted" style="margin-bottom:8px;">静态分配里填“标签”即可套用此处规则（例如 istoreos、8）。</div>
    <form method="post" style="margin-bottom:10px;">
      <input type="hidden" name="action" value="save_template" />
      <div class="grid">
        <div>
          <label>标签名</label>
          <input name="template_tag" placeholder="例如 istoreos 或 8" />
        </div>
        <div>
          <label>标签网关（Option 3）</label>
          <input name="template_gateway" placeholder="例如 10.0.0.2" />
        </div>
      </div>
      <label>标签 DNS（Option 6，多个逗号分隔）</label>
      <input name="template_dns" placeholder="例如 10.0.0.2 或 223.5.5.5,119.29.29.29" />
      <div style="margin-top:10px"><button class="gray" type="submit">新增 / 更新标签模板</button></div>
    </form>
    <table>
      <thead>
        <tr><th>标签</th><th>网关(3)</th><th>DNS(6)</th><th>操作</th></tr>
      </thead>
      <tbody>
HTML_TAG_END

tag_found=0
for tsec in $(uci -q show dhcp | sed -n "s/^dhcp\.\([^.=]*\)=tag$/\1/p"); do
  tname=$(uci -q get dhcp."$tsec".tag)
  [ -z "$tname" ] && continue
  case "$tname" in
    adv_*) continue ;;
  esac
  tgw=$(get_section_option_value "$tsec" 3)
  tdns=$(get_section_option_value "$tsec" 6)
  tag_found=1
  printf '<tr>'
  printf '<td>%s</td>' "$(html_escape "$tname")"
  printf '<td>%s</td>' "$(html_escape "$tgw")"
  printf '<td>%s</td>' "$(html_escape "$tdns")"
  printf '<td class="actions">'
  printf '<form method="post"><input type="hidden" name="action" value="delete_template" /><input type="hidden" name="template_sec" value="%s" /><button class="red" type="submit">删除</button></form>' "$(html_escape "$tsec")"
  printf '</td>'
  printf '</tr>\n'
done
[ "$tag_found" -eq 0 ] && echo '<tr><td colspan="4" class="muted">暂无可用标签模板</td></tr>'

cat <<'HTML_TAG_CLOSE'
      </tbody>
    </table>
  </div>
HTML_TAG_CLOSE

lan_ip=$(uci -q get network.lan.ipaddr)
lan_prefix=""
case "$lan_ip" in
  *.*.*.*) lan_prefix=${lan_ip%.*} ;;
esac

dynamic_lan_rows="/tmp/dhcp_adv_lan_rows.$$"
dynamic_other_rows="/tmp/dhcp_adv_other_rows.$$"
rm -f "$dynamic_lan_rows" "$dynamic_other_rows"
: > "$dynamic_lan_rows"
: > "$dynamic_other_rows"
dynamic_lan_found=0
dynamic_other_found=0

if [ -f /tmp/dhcp.leases ]; then
  while read -r lexp lmac lip lhost lcid; do
    [ -z "$lmac" ] && continue
    lmac=$(normalize_mac "$lmac")
    if is_static_mac "$lmac"; then
      lease_type='静态保留'
      lease_action='-'
    else
      lease_type='动态'
      lease_action="<a class=\"link\" href=\"/cgi-bin/dhcp_adv.sh?name=$(html_escape "$lhost")&mac=$(html_escape "$lmac")&ip=$(html_escape "$lip")\">转为静态</a>"
    fi
    [ "$lhost" = "*" ] && lhost=""
    lremain=$(format_lease_expire "$lexp")
    out_file="$dynamic_other_rows"
    if [ -n "$lan_prefix" ]; then
      case "$lip" in
        "$lan_prefix".*)
          out_file="$dynamic_lan_rows"
          dynamic_lan_found=1
          ;;
        *)
          dynamic_other_found=1
          ;;
      esac
    else
      dynamic_other_found=1
    fi
    {
      printf '<tr>'
      printf '<td>%s</td>' "$(html_escape "$lhost")"
      printf '<td>%s</td>' "$(html_escape "$lmac")"
      printf '<td>%s</td>' "$(html_escape "$lip")"
      printf '<td>%s</td>' "$(html_escape "$lease_type")"
      printf '<td>%s</td>' "$(html_escape "$lremain")"
      printf '<td>%s</td>' "$lease_action"
      printf '</tr>\n'
    } >> "$out_file"
  done < /tmp/dhcp.leases
fi

cat <<HTML_DYN_LAN_HEAD
  <div class="card">
    <h3 style="margin:0 0 10px;">动态租约（LAN 当前已分配）</h3>
    <div class="muted" style="margin-bottom:8px;">来源：/tmp/dhcp.leases（包含静态与动态，LAN 前缀：${lan_prefix:-未知}.*）</div>
    <table>
      <thead>
        <tr><th>主机名</th><th>MAC</th><th>IP</th><th>类型</th><th>剩余租期</th><th>操作</th></tr>
      </thead>
      <tbody>
HTML_DYN_LAN_HEAD

if [ "$dynamic_lan_found" -eq 1 ]; then
  cat "$dynamic_lan_rows"
else
  echo '<tr><td colspan="6" class="muted">暂无 LAN 动态租约记录</td></tr>'
fi

cat <<'HTML_DYN_LAN_END'
      </tbody>
    </table>
  </div>

  <div class="card">
    <h3 style="margin:0 0 10px;">其他网段动态租约（如 MIoT）</h3>
    <table>
      <thead>
        <tr><th>主机名</th><th>MAC</th><th>IP</th><th>类型</th><th>剩余租期</th><th>操作</th></tr>
      </thead>
      <tbody>
HTML_DYN_LAN_END

if [ "$dynamic_other_found" -eq 1 ]; then
  cat "$dynamic_other_rows"
else
  echo '<tr><td colspan="6" class="muted">暂无其他网段动态租约记录</td></tr>'
fi
rm -f "$dynamic_lan_rows" "$dynamic_other_rows"

cat <<'HTML_BOTTOM'
      </tbody>
    </table>
  </div>
</div>
</body>
</html>
HTML_BOTTOM
