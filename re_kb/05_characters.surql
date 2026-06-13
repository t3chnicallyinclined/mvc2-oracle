-- ============================================================================
-- 05: roster characters (char_id == PLxx hex == S_PLxx index) + Ryu anim groups
-- Source: char_prg/buildSPL.sh #NN Name manifest (AUTHORITATIVE map).
-- ============================================================================
USE NS re DB kb;

UPSERT character:pl00 SET char_id='0x00', name='Ryu', spl_file='S_PL00.asm', atlas='PL00', note='char_id 0x00. S_PL00 = Ryu (the emitter reference char). 26 anim groups feed loc_8c034e8c.';
UPSERT character:pl01 SET char_id='0x01', name='Zangief', spl_file='S_PL01.asm', atlas='PL01', note='char_id 0x01. S_PL01 = Zangief (NOT Ryu -- common mislink; Paxtez header reads "Zangiev Programming").';
UPSERT character:pl02 SET char_id='0x02', name='Guile', spl_file='S_PL02.asm', atlas='PL02', note='char_id 0x02.';
UPSERT character:pl03 SET char_id='0x03', name='Morrigan', spl_file='S_PL03.asm', atlas='PL03', note='char_id 0x03.';
UPSERT character:pl04 SET char_id='0x04', name='Anakaris', spl_file='S_PL04.asm', atlas='PL04', note='char_id 0x04.';
UPSERT character:pl05 SET char_id='0x05', name='Strider', spl_file='S_PL05.asm', atlas='PL05', note='char_id 0x05.';
UPSERT character:pl06 SET char_id='0x06', name='Cyclops', spl_file='S_PL06.asm', atlas='PL06', note='char_id 0x06.';
UPSERT character:pl07 SET char_id='0x07', name='Wolverine (metal)', spl_file='S_PL07.asm', atlas='PL07', note='char_id 0x07.';
UPSERT character:pl08 SET char_id='0x08', name='Psylocke', spl_file='S_PL08.asm', atlas='PL08', note='char_id 0x08.';
UPSERT character:pl09 SET char_id='0x09', name='Iceman', spl_file='S_PL09.asm', atlas='PL09', note='char_id 0x09.';
UPSERT character:pl0a SET char_id='0x0A', name='Rogue', spl_file='S_PL0A.asm', atlas='PL0A', note='char_id 0x0A.';
UPSERT character:pl0b SET char_id='0x0B', name='Captain America', spl_file='S_PL0B.asm', atlas='PL0B', note='char_id 0x0B.';
UPSERT character:pl0c SET char_id='0x0C', name='Spider-Man', spl_file='S_PL0C.asm', atlas='PL0C', note='char_id 0x0C.';
UPSERT character:pl0d SET char_id='0x0D', name='Hulk', spl_file='S_PL0D.asm', atlas='PL0D', note='char_id 0x0D.';
UPSERT character:pl0e SET char_id='0x0E', name='Venom', spl_file='S_PL0E.asm', atlas='PL0E', note='char_id 0x0E.';
UPSERT character:pl0f SET char_id='0x0F', name='Dr. Doom', spl_file='S_PL0F.asm', atlas='PL0F', note='char_id 0x0F.';
UPSERT character:pl10 SET char_id='0x10', name='Tron', spl_file='S_PL10.asm', atlas='PL10', note='char_id 0x10.';
UPSERT character:pl11 SET char_id='0x11', name='Jill', spl_file='S_PL11.asm', atlas='PL11', note='char_id 0x11.';
UPSERT character:pl12 SET char_id='0x12', name='Hayato', spl_file='S_PL12.asm', atlas='PL12', note='char_id 0x12.';
UPSERT character:pl13 SET char_id='0x13', name='Ruby Heart', spl_file='S_PL13.asm', atlas='PL13', note='char_id 0x13.';
UPSERT character:pl14 SET char_id='0x14', name='SonSon', spl_file='S_PL14.asm', atlas='PL14', note='char_id 0x14.';
UPSERT character:pl15 SET char_id='0x15', name='Amingo', spl_file='S_PL15.asm', atlas='PL15', note='char_id 0x15.';
UPSERT character:pl16 SET char_id='0x16', name='Marrow', spl_file='S_PL16.asm', atlas='PL16', note='char_id 0x16.';
UPSERT character:pl17 SET char_id='0x17', name='Cable', spl_file='S_PL17.asm', atlas='PL17', note='char_id 0x17. mapped: re-catalog PL17-cable.';
UPSERT character:pl18 SET char_id='0x18', name='Abyss1', spl_file='S_PL18.asm', atlas='PL18', note='char_id 0x18 (Abyss phase 1).';
UPSERT character:pl19 SET char_id='0x19', name='Abyss2', spl_file='S_PL19.asm', atlas='PL19', note='char_id 0x19 (Abyss phase 2).';
UPSERT character:pl1a SET char_id='0x1A', name='Abyss3', spl_file='S_PL1A.asm', atlas='PL1A', note='char_id 0x1A (Abyss phase 3).';
UPSERT character:pl1b SET char_id='0x1B', name='Chun-Li', spl_file='S_PL1B.asm', atlas='PL1B', note='char_id 0x1B.';
UPSERT character:pl1c SET char_id='0x1C', name='Mega Man', spl_file='S_PL1C.asm', atlas='PL1C', note='char_id 0x1C.';
UPSERT character:pl1d SET char_id='0x1D', name='Roll', spl_file='S_PL1D.asm', atlas='PL1D', note='char_id 0x1D.';
UPSERT character:pl1e SET char_id='0x1E', name='Akuma', spl_file='S_PL1E.asm', atlas='PL1E', note='char_id 0x1E.';
UPSERT character:pl1f SET char_id='0x1F', name='B.B.Hood', spl_file='S_PL1F.asm', atlas='PL1F', note='char_id 0x1F.';
UPSERT character:pl20 SET char_id='0x20', name='Felicia', spl_file='S_PL20.asm', atlas='PL20', note='char_id 0x20.';
UPSERT character:pl21 SET char_id='0x21', name='Charlie', spl_file='S_PL21.asm', atlas='PL21', note='char_id 0x21.';
UPSERT character:pl22 SET char_id='0x22', name='Sakura', spl_file='S_PL22.asm', atlas='PL22', note='char_id 0x22.';
UPSERT character:pl23 SET char_id='0x23', name='Dan', spl_file='S_PL23.asm', atlas='PL23', note='char_id 0x23.';
UPSERT character:pl24 SET char_id='0x24', name='Cammy', spl_file='S_PL24.asm', atlas='PL24', note='char_id 0x24.';
UPSERT character:pl25 SET char_id='0x25', name='Dhalsim', spl_file='S_PL25.asm', atlas='PL25', note='char_id 0x25.';
UPSERT character:pl26 SET char_id='0x26', name='M.Bison (Dictator)', spl_file='S_PL26.asm', atlas='PL26', note='char_id 0x26.';
UPSERT character:pl27 SET char_id='0x27', name='Ken', spl_file='S_PL27.asm', atlas='PL27', note='char_id 0x27.';
UPSERT character:pl28 SET char_id='0x28', name='Gambit', spl_file='S_PL28.asm', atlas='PL28', note='char_id 0x28.';
UPSERT character:pl29 SET char_id='0x29', name='Juggernaut', spl_file='S_PL29.asm', atlas='PL29', note='char_id 0x29.';
UPSERT character:pl2a SET char_id='0x2A', name='Storm', spl_file='S_PL2A.asm', atlas='PL2A', note='char_id 0x2A. THE fully-mapped reference character (re-catalog PL2A-storm.md).';
UPSERT character:pl2b SET char_id='0x2B', name='Sabretooth', spl_file='S_PL2B.asm', atlas='PL2B', note='char_id 0x2B.';
UPSERT character:pl2c SET char_id='0x2C', name='Magneto', spl_file='S_PL2C.asm', atlas='PL2C', note='char_id 0x2C. mapped: re-catalog PL2C-magneto.';
UPSERT character:pl2d SET char_id='0x2D', name='Shuma-Gorath', spl_file='S_PL2D.asm', atlas='PL2D', note='char_id 0x2D.';
UPSERT character:pl2e SET char_id='0x2E', name='War Machine', spl_file='S_PL2E.asm', atlas='PL2E', note='char_id 0x2E.';
UPSERT character:pl2f SET char_id='0x2F', name='Silver Samurai', spl_file='S_PL2F.asm', atlas='PL2F', note='char_id 0x2F.';
UPSERT character:pl30 SET char_id='0x30', name='Omega Red', spl_file='S_PL30.asm', atlas='PL30', note='char_id 0x30.';
UPSERT character:pl31 SET char_id='0x31', name='Spiral', spl_file='S_PL31.asm', atlas='PL31', note='char_id 0x31.';
UPSERT character:pl32 SET char_id='0x32', name='Colossus', spl_file='S_PL32.asm', atlas='PL32', note='char_id 0x32.';
UPSERT character:pl33 SET char_id='0x33', name='Iron Man', spl_file='S_PL33.asm', atlas='PL33', note='char_id 0x33.';
UPSERT character:pl34 SET char_id='0x34', name='Sentinel', spl_file='S_PL34.asm', atlas='PL34', note='char_id 0x34.';
UPSERT character:pl35 SET char_id='0x35', name='Blackheart', spl_file='S_PL35.asm', atlas='PL35', note='char_id 0x35.';
UPSERT character:pl36 SET char_id='0x36', name='Thanos', spl_file='S_PL36.asm', atlas='PL36', note='char_id 0x36.';
UPSERT character:pl37 SET char_id='0x37', name='Jin', spl_file='S_PL37.asm', atlas='PL37', note='char_id 0x37.';
UPSERT character:pl38 SET char_id='0x38', name='Captain Commando', spl_file='S_PL38.asm', atlas='PL38', note='char_id 0x38.';
UPSERT character:pl39 SET char_id='0x39', name='Wolverine (bone)', spl_file='S_PL39.asm', atlas='PL39', note='char_id 0x39.';
UPSERT character:pl3a SET char_id='0x3A', name='Servbot', spl_file='S_PL3A.asm', atlas='PL3A', note='char_id 0x3A.';

-- ---- Ryu animation groups (the group-id immediates feeding r5 -> loc_8c034e8c)
-- within anotak's 0x00-0x1B group range; high values are non-group args.
UPSERT animgroup:pl00_g00 SET char='pl00', group_id='0x00', note='Ryu anim group 0x00 (feeds loc_8c034e8c r5).';
UPSERT animgroup:pl00_g01 SET char='pl00', group_id='0x01', note='Ryu anim group 0x01.';
UPSERT animgroup:pl00_g02 SET char='pl00', group_id='0x02', note='Ryu anim group 0x02.';
UPSERT animgroup:pl00_g05 SET char='pl00', group_id='0x05', note='Ryu anim group 0x05.';
UPSERT animgroup:pl00_g08 SET char='pl00', group_id='0x08', note='Ryu anim group 0x08.';
UPSERT animgroup:pl00_g09 SET char='pl00', group_id='0x09', note='Ryu anim group 0x09.';
UPSERT animgroup:pl00_g0a SET char='pl00', group_id='0x0A', note='Ryu anim group 0x0A.';
UPSERT animgroup:pl00_g0c SET char='pl00', group_id='0x0C', note='Ryu anim group 0x0C.';
UPSERT animgroup:pl00_g0f SET char='pl00', group_id='0x0F', note='Ryu anim group 0x0F.';
UPSERT animgroup:pl00_g12 SET char='pl00', group_id='0x12', note='Ryu anim group 0x12.';
UPSERT animgroup:pl00_g13 SET char='pl00', group_id='0x13', note='Ryu anim group 0x13.';
UPSERT animgroup:pl00_g14 SET char='pl00', group_id='0x14', note='Ryu anim group 0x14.';
UPSERT animgroup:pl00_g15 SET char='pl00', group_id='0x15', note='Ryu anim group 0x15.';
UPSERT animgroup:pl00_g16 SET char='pl00', group_id='0x16', note='Ryu anim group 0x16.';
UPSERT animgroup:pl00_g1d SET char='pl00', group_id='0x1D', note='Ryu anim group 0x1D (high; may be a non-group arg).';

RELATE character:pl00->owns->animgroup:pl00_g00;
RELATE character:pl00->owns->animgroup:pl00_g01;
RELATE character:pl00->owns->animgroup:pl00_g02;
RELATE character:pl00->owns->animgroup:pl00_g05;
RELATE character:pl00->owns->animgroup:pl00_g08;
RELATE character:pl00->owns->animgroup:pl00_g09;
RELATE character:pl00->owns->animgroup:pl00_g0a;
RELATE character:pl00->owns->animgroup:pl00_g0c;
RELATE character:pl00->owns->animgroup:pl00_g0f;
RELATE character:pl00->owns->animgroup:pl00_g12;
RELATE character:pl00->owns->animgroup:pl00_g13;
RELATE character:pl00->owns->animgroup:pl00_g14;
RELATE character:pl00->owns->animgroup:pl00_g15;
RELATE character:pl00->owns->animgroup:pl00_g16;
RELATE character:pl00->owns->animgroup:pl00_g1d;

-- slot -> character ownership (live assignment varies; example seed for ref char)
-- (left intentionally sparse; assigned live per match from character_id@+0x001)
