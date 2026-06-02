(function () {
  const G = Blockly.Lua;
  const NONE = G.ORDER_NONE;
  const ATOMIC = G.ORDER_ATOMIC;
  const HIGH = G.ORDER_HIGH;

  const val = (block, name, fallback) => G.valueToCode(block, name, NONE) || fallback;

  G.forBlock["rbx_print"] = (b) => "print(" + val(b, "TEXT", '""') + ")\n";
  G.forBlock["rbx_warn"] = (b) => "warn(" + val(b, "TEXT", '""') + ")\n";
  G.forBlock["rbx_wait"] = (b) => "task.wait(" + val(b, "SECONDS", "1") + ")\n";

  G.forBlock["rbx_players_count"] = () => ['#game:GetService("Players"):GetPlayers()', HIGH];
  G.forBlock["rbx_current_player"] = () => ["_player", ATOMIC];

  G.forBlock["rbx_find_player"] = function (b) {
    const name = G.provideFunction_("findPlayer", [
      "local function " + G.FUNCTION_NAME_PLACEHOLDER_ + "(name)",
      '\tfor _, p in game:GetService("Players"):GetPlayers() do',
      "\t\tif string.lower(p.Name) == string.lower(name) then return p end",
      "\tend",
      "\treturn nil",
      "end",
    ]);
    return [name + "(" + val(b, "NAME", '""') + ")", HIGH];
  };

  G.forBlock["rbx_for_each_player"] = function (b) {
    const branch = G.statementToCode(b, "DO");
    return 'for _, _player in game:GetService("Players"):GetPlayers() do\n' + branch + "end\n";
  };

  G.forBlock["rbx_kick"] = function (b) {
    return "do local _t = " + val(b, "PLAYER", "nil") + " if _t then _t:Kick(" + val(b, "REASON", '""') + ") end end\n";
  };

  G.forBlock["rbx_set_walkspeed"] = function (b) {
    return "do local _t = " + val(b, "PLAYER", "nil")
      + ' local _c = _t and _t.Character local _h = _c and _c:FindFirstChildOfClass("Humanoid")'
      + " if _h then _h.WalkSpeed = " + val(b, "SPEED", "16") + " end end\n";
  };

  G.forBlock["rbx_set_health"] = function (b) {
    return "do local _t = " + val(b, "PLAYER", "nil")
      + ' local _c = _t and _t.Character local _h = _c and _c:FindFirstChildOfClass("Humanoid")'
      + " if _h then _h.Health = " + val(b, "AMOUNT", "100") + " end end\n";
  };

  G.forBlock["rbx_teleport"] = function (b) {
    return "do local _t = " + val(b, "PLAYER", "nil") + " local _d = " + val(b, "TARGET", "nil")
      + " if _t and _d and _t.Character and _d.Character then _t.Character:PivotTo(_d.Character:GetPivot()) end end\n";
  };

  G.forBlock["rbx_join"] = function (b) {
    return ["tostring(" + val(b, "A", '""') + ") .. tostring(" + val(b, "B", '""') + ")", G.ORDER_CONCATENATION];
  };

  G.forBlock["ui_set_title"] = (b) => "ui.setTitle(" + val(b, "TEXT", '""') + ")\n";
  G.forBlock["ui_notify"] = (b) => "ui.notify(" + val(b, "TEXT", '""') + ")\n";
  G.forBlock["ui_log"] = (b) => "ui.log(" + val(b, "TEXT", '""') + ")\n";
  G.forBlock["ui_add_button"] = (b) => "ui.addButton(" + val(b, "LABEL", '""') + ")\n";

  const color = (b) => "Color3.fromRGB(" + val(b, "R", "0") + ", " + val(b, "G", "0") + ", " + val(b, "B", "0") + ")";
  G.forBlock["ui_set_accent"] = (b) => "ui.setAccent(" + color(b) + ")\n";
  G.forBlock["ui_set_background"] = (b) => "ui.setBackground(" + color(b) + ")\n";

  function runtimeBody(block) {
    const branch = G.statementToCode(block, "DO");
    return branch.trim() === "" ? "" : branch;
  }

  G.forBlock["runtime_on_player_added"] = function (b) {
    return "function CustomRuntime.onPlayerAdded(_player)\n" + runtimeBody(b) + "end\n";
  };
  G.forBlock["runtime_on_player_removing"] = function (b) {
    return "function CustomRuntime.onPlayerRemoving(_player)\n" + runtimeBody(b) + "end\n";
  };
  G.forBlock["runtime_on_request"] = function (b) {
    return "function CustomRuntime.onRequestReceived(_player, _payload)\n" + runtimeBody(b) + "\treturn true\nend\n";
  };
  G.forBlock["runtime_register_action"] = function (b) {
    const name = b.getFieldValue("NAME") || "action";
    return 'CustomRuntime.customActions[' + G.quote_(name) + "] = function(_player, _args, _emit)\n" + runtimeBody(b) + "end\n";
  };

  G.forBlock["runtime_the_player"] = () => ["_player", ATOMIC];
  G.forBlock["runtime_action_arg"] = function (b) {
    const key = b.getFieldValue("KEY") || "arg";
    return ["(_args and _args[" + G.quote_(key) + "])", HIGH];
  };
  G.forBlock["runtime_request_mode_is"] = () => ["(_payload.mode == \"lua\")", HIGH];
  G.forBlock["runtime_reject_request"] = () => "return false\n";
  G.forBlock["runtime_emit"] = (b) => "if _emit then _emit(" + val(b, "TEXT", '""') + ") end\n";
})();
