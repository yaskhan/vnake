@@in# "m.name = fn (v string) !string {"
@@in# "return error('Name too short')"
@@in# "}(m.name) !"
@@notin# "fn User_validate_name"
