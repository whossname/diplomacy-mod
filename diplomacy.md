Summary of State Behavior
Independent: Can form Partnerships or swear Fealty.
```mermaid
%%{init: {'theme': 'dark', 'themeVariables': {'background': '#1e1e1e'}}}%%
flowchart TD
    %% Node Styles
    classDef ind fill:#01579b,stroke:#29b6f6,stroke-width:2px,color:#ffffff;
    classDef part fill:#1b5e20,stroke:#66bb6a,stroke-width:2px,color:#ffffff;
    classDef king fill:#e65100,stroke:#ffa726,stroke-width:2px,color:#ffffff;
    classDef vassal fill:#b71c1c,stroke:#ef5350,stroke-width:2px,color:#ffffff;

    %% Define Nodes with HTML formatting
    I["<b>Independent</b><br>• 1+ Commanders<br>• Full diplomatic rights"]:::ind
    P["<b>Partnership</b><br>• Max 2 players<br>• 1+ Commanders each<br>• Equal partners"]:::part
    K["<b>King (Fealty Leader)</b><br>• 1+ Commanders<br>• Can have many vassals"]:::king
    V["<b>Vassal (Subjugated)</b><br>• 0 Commanders<br>• No diplomatic rights"]:::vassal

    %% Transitions
    Start((Match Start)) --> I

    P --->|Partner loses last Cmdr OR Accept Vassal| K

    %% Independent Transitions
    I <--->|Form / Dissolve Agreement| P
    I --->|Accept a Vassal| K
    I --->|Swear Fealty| V
    V --->|Obtain Cmdr| I

    %% Partnership Transitions
    P -->|Lose last Cmdr <br> OR Swear Fealty| V
    
    %% Self-loop for replacing partnership
    P -->|Accept new partnership| P
```

Summary of State Behavior
Independent: Can form Partnerships or swear Fealty.

Partnership: Two equal players. If one loses their Commander, the partnership instantly collapses into a Fealty relationship where the survivor becomes the King and the fallen player becomes the Vassal.

Vassal: Trapped with 0 commanders and locked out of diplomacy

King: Can have many vassals

If you aren't a vassal and lose your last commander you are out of the game.

If a King loses their last commander the King and all of their vassals are out of the game.
