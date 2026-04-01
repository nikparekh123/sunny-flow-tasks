import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

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
    const { name, pincode } = await req.json();

    if (!name || typeof name !== "string" || !name.trim()) {
      return new Response(
        JSON.stringify({ error: "Name is required." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!pincode || typeof pincode !== "string" || !/^\d{4}$/.test(pincode)) {
      return new Response(
        JSON.stringify({ error: "A valid 4-digit pincode is required." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    // Check if pincode already exists in member_pincodes
    const { data: existing } = await admin
      .from("member_pincodes")
      .select("id")
      .eq("pincode", pincode)
      .maybeSingle();

    if (existing) {
      return new Response(
        JSON.stringify({ error: "This pincode is already in use." }),
        { status: 409, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Create auth user with generated email
    const email = `pin_${pincode}@sunnyfi.local`;
    const password = `pin_${pincode}_${Date.now()}`;

    const { data: created, error: createError } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { full_name: name.trim() },
    });

    if (createError) throw createError;

    const userId = created.user.id;

    // Create team_member row
    const { error: memberError } = await admin.from("team_members").insert({
      user_id: userId,
      name: name.trim(),
      initials: getInitials(name.trim()),
      color: pickColor(userId),
      role: "member",
    });

    if (memberError) throw memberError;

    // Store pincode in member_pincodes
    const { error: pinError } = await admin.from("member_pincodes").insert({
      user_id: userId,
      pincode,
    });

    if (pinError) throw pinError;

    return new Response(
      JSON.stringify({ success: true, name: name.trim(), pincode }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: err.message || "Server error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
