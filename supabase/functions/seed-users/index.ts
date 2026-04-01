import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const USERS = [
  { email: "nik@sunnyfi.co", password: "niknik", name: "Nik Parekh", role: "admin" },
  { email: "ary@sunnyfi.co", password: "aryary", name: "Ary LaRocca", role: "admin" },
  { email: "rad@sunnyfi.co", password: "radrad", name: "Rad Rahmouni", role: "member" },
  { email: "kushal@sunnyfi.co", password: "kushalkushal", name: "Kushal Jain", role: "member" },
];

const MEMBER_COLORS = ["blue", "green", "purple", "orange", "pink", "teal"];

const getInitials = (name: string) =>
  name.split(" ").filter(Boolean).map((w) => w[0]).join("").toUpperCase().slice(0, 2);

const pickColor = (seed: string) => {
  const total = seed.split("").reduce((sum, ch) => sum + ch.charCodeAt(0), 0);
  return MEMBER_COLORS[total % MEMBER_COLORS.length];
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const results = [];

    for (const u of USERS) {
      const { data: existing } = await admin.auth.admin.listUsers();
      const found = existing?.users?.find((x: any) => x.email === u.email);

      let userId: string;

      if (found) {
        userId = found.id;
        results.push({ email: u.email, status: "exists" });
      } else {
        const { data: created, error } = await admin.auth.admin.createUser({
          email: u.email,
          password: u.password,
          email_confirm: true,
          user_metadata: { full_name: u.name },
        });
        if (error) throw error;
        userId = created.user.id;
        results.push({ email: u.email, status: "created" });
      }

      // Upsert team_members
      const { error: memberError } = await admin
        .from("team_members")
        .upsert(
          {
            user_id: userId,
            name: u.name,
            initials: getInitials(u.name),
            color: pickColor(userId),
            role: u.role,
          },
          { onConflict: "user_id" }
        );

      if (memberError) {
        const { data: existingMember } = await admin
          .from("team_members")
          .select("id")
          .eq("user_id", userId)
          .maybeSingle();

        if (existingMember) {
          await admin
            .from("team_members")
            .update({ name: u.name, role: u.role })
            .eq("user_id", userId);
        } else {
          await admin.from("team_members").insert({
            user_id: userId,
            name: u.name,
            initials: getInitials(u.name),
            color: pickColor(userId),
            role: u.role,
          });
        }
      }
    }

    return new Response(JSON.stringify({ success: true, results }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
