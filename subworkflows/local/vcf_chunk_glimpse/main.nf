include { GLIMPSE_CHUNK           } from '../../../modules/nf-core/glimpse/chunk'
include { GLIMPSE2_CHUNK          } from '../../../modules/nf-core/glimpse2/chunk'
include { GLIMPSE2_SPLITREFERENCE } from '../../../modules/nf-core/glimpse2/splitreference'

workflow VCF_CHUNK_GLIMPSE {

    take:
    ch_reference  // channel: [ [panel, chr], vcf, csi ]
    ch_map        // channel  (optional): [ [chr], map ]

    main:

    ch_versions = Channel.empty()
    // Add chromosome to channel
    ch_vcf_csi_chr = ch_reference
        .map{metaPC, vcf, csi -> [metaPC, vcf, csi, metaPC.chr]}

    // Make chunks with Glimpse1
    GLIMPSE_CHUNK(ch_vcf_csi_chr)
    ch_versions = ch_versions.mix(GLIMPSE_CHUNK.out.versions)

    // Rearrange chunks into channel for QUILT
    ch_chunks_quilt = GLIMPSE_CHUNK.out.chunk_chr
        .splitText()
        .map { metaPC, line ->
            def fields = line.split("\t")
            def startEnd = fields[2].split(':')[1].split('-')
            [metaPC, metaPC.chr, startEnd[0], startEnd[1]]
        }

    // Rearrange chunks into channel for GLIMPSE1
    ch_chunks_glimpse1 = GLIMPSE_CHUNK.out.chunk_chr
        .splitCsv(
            header: ['ID', 'Chr', 'RegionIn', 'RegionOut', 'Size1', 'Size2'],
            sep: "\t", skip: 0
        )
        .map { metaPC, it -> [metaPC, it["RegionIn"], it["RegionOut"]]}

    // Make chunks with Glimpse2 (does not work with "sequential" mode)
    chunk_model = "recursive"

    ch_input_glimpse2 = ch_vcf_csi_chr
        .map{
            metaPC, vcf, csi, chr -> [metaPC.subMap("chr"), metaPC, vcf, csi, chr]
        }
        .join(ch_map)
        .map{
            _metaC, metaPC, vcf, csi, chr, gmap -> [metaPC, vcf, csi, chr, gmap]
        }
    GLIMPSE2_CHUNK ( ch_input_glimpse2, chunk_model )
    ch_versions = ch_versions.mix( GLIMPSE2_CHUNK.out.versions.first() )

    // Rearrange channels
    ch_chunks_glimpse2 = GLIMPSE2_CHUNK.out.chunk_chr
        .splitCsv(
            header: [
                'ID', 'Chr', 'RegionBuf', 'RegionCnk', 'WindowCm',
                'WindowMb', 'NbTotVariants', 'NbComVariants'
            ], sep: "\t", skip: 0
        )
        .map { metaPC, it -> [metaPC, it["RegionBuf"], it["RegionCnk"]]}

    // Split reference panel in bin files
    // Segmentation fault occurs in small-sized panels
    // Should be run only in full-sized panels

    ch_bins = [[]]

    if (params.binaryref == true) {
        // Create channel to split reference
        split_input = ch_reference.join(ch_chunks_glimpse2)

        // Create a binary reference panel for quick reading time
        GLIMPSE2_SPLITREFERENCE( split_input, ch_map )
        ch_versions = ch_versions.mix( GLIMPSE2_SPLITREFERENCE.out.versions.first() )

        ch_bins = GLIMPSE2_SPLITREFERENCE.out.bin_ref
    }

    emit:
    chunks                    = GLIMPSE_CHUNK.out.chunk_chr           // channel:  [ [panel, chr], txt ]
    chunks_quilt              = ch_chunks_quilt                       // channel:  [ [panel, chr], chr,  start, end ]
    chunks_glimpse1           = ch_chunks_glimpse1                    // channel:  [ [panel, chr], chr,  region1, region2 ]
    chunks_glimpse2           = ch_chunks_glimpse2                    // channel:  [ [panel, chr], chr,  region1, region2 ]
    binary                    = ch_bins                               // channel:  [ [panel, chr], bin]
    versions                  = ch_versions                           // channel:  [ versions.yml ]
}
