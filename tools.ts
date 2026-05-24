import { z } from "zod";

const tools = {
    // read: z.object({
    //     name: z.string().describe("name of the file"),
    // }).describe("read a file"),
    bash: z.object({
        command: z.string().describe(
            "The exact shell command to execute. Supports multiline scripts, piping (|), and redirection (>). Do not include conversational text or markdown code blocks here."
        ),
    }).describe(
        "Executes an arbitrary command in a non-interactive bash shell on the host machine. Current environment: Linux. Use this to inspect files, manage directories, run processes, or install dependencies. WARNING: Ensure commands are safe, complete, and do not hang indefinitely (avoid un-flagged commands like interactive 'sudo' or raw 'npm start')."
    )
};

function parse(name: string, obj: z.ZodObject): string {
    const schema = obj.toJSONSchema({ target: "openapi-3.0" });
    return JSON.stringify({
        type: "function" as const,
        function: {
            name, description: schema.description,
            parameters: schema.properties,
        }
    }, null, 2);
}

console.log(Object.entries(tools).map(([key, value]) => parse(key, value)).join("\n"));
